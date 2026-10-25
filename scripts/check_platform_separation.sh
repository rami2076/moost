#!/usr/bin/env bash
#
# プラットフォーム分離の検査（ADR-006 / #105）
#
# 「macOS 側と Windows 側のコードが独立していること」を機械的に確かめる。
# 混入の典型は 3 種類:
#   1. 言語の混在（apps/macos に C#、apps/windows に Swift）
#   2. ビルド定義の相互参照（apps/windows の csproj が ../macos を取り込む 等）
#   3. 条件コンパイル（#if os(Windows) / OSPlatform.OSX など）
# 加えて、共有してよいのが spec/ だけであることと、CI のトリガが交差しないことを見る。
#
# コメントに相手側のパスを書くのは移植の手がかりとして望ましいので許容する
# （参照の検査はビルド定義からコメントを除いた実体だけを対象にする）。
#
# 使い方: bash scripts/check_platform_separation.sh
# 失敗時は終了コード 1。CI（separation ジョブ）がこれを必須チェックにする。
set -uo pipefail

failures=0

fail() {
  echo "NG: $*" >&2
  failures=$((failures + 1))
}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root" || exit 1

# ---------------------------------------------------------------------------
# 1. 言語の非混在
# ---------------------------------------------------------------------------
if find apps/macos \( -name '*.cs' -o -name '*.csproj' -o -name '*.props' \
      -o -name '*.sln' -o -name '*.slnx' \) -print -quit 2>/dev/null | grep -q .; then
  fail "apps/macos に C#/.NET のファイルがあります（Windows 実装は apps/windows に置く）"
fi

if find apps/windows \( -name '*.swift' -o -name 'Package.swift' \) -print -quit 2>/dev/null | grep -q .; then
  fail "apps/windows に Swift のファイルがあります（macOS 実装は apps/macos に置く）"
fi

# ---------------------------------------------------------------------------
# 2. ビルド定義の相互参照の禁止（XML コメントを除いた実体だけを見る）
# ---------------------------------------------------------------------------
xml_refs() {
  local tree=$1
  find "$tree" \( -name '*.csproj' -o -name '*.props' -o -name '*.slnx' -o -name '*.sln' \) -print0 2>/dev/null \
    | xargs -0 -r awk '
        FNR == 1 { incomment = 0 }
        /<!--/   { incomment = 1 }
        incomment == 0 { print FILENAME ":" FNR ":" $0 }
        /-->/    { incomment = 0 }
      ' 2>/dev/null || true
}

cross_windows=$(xml_refs apps/windows | grep -E 'apps/macos|\.\./macos|\.\.\\macos' || true)
if [ -n "$cross_windows" ]; then
  echo "$cross_windows" >&2
  fail "apps/windows のビルド定義が macOS 側を参照しています"
fi

dart_ref=$(xml_refs apps/windows | grep -E 'packages/core|packages\\core' || true)
if [ -n "$dart_ref" ]; then
  echo "$dart_ref" >&2
  fail "apps/windows が Dart 参照実装（packages/core）を参照しています"
fi

# Swift 側は Package.swift のコメントを除いて判定する
if [ -f apps/macos/Package.swift ]; then
  cross_macos=$(grep -v '^[[:space:]]*//' apps/macos/Package.swift \
    | grep -nE 'apps/windows|\.\./windows' || true)
  if [ -n "$cross_macos" ]; then
    echo "$cross_macos" >&2
    fail "apps/macos/Package.swift が Windows 側を参照しています"
  fi
fi

# ---------------------------------------------------------------------------
# 3. 条件コンパイルの禁止（本番コードのみ・テストは除く）
# ---------------------------------------------------------------------------
cond_macos=$(grep -rIn --include='*.swift' \
  -e '#if os(Windows)' -e 'canImport(Windows)' -e 'OS_WINDOWS' \
  apps/macos/Sources 2>/dev/null || true)
if [ -n "$cond_macos" ]; then
  echo "$cond_macos" >&2
  fail "apps/macos/Sources に Windows 向けの条件コンパイルがあります"
fi

cond_windows=$(grep -rIn --include='*.cs' \
  -e 'OSPlatform\.OSX' -e 'OS_MACOS' -e 'IsOSPlatform' \
  apps/windows/src 2>/dev/null || true)
if [ -n "$cond_windows" ]; then
  echo "$cond_windows" >&2
  fail "apps/windows/src に macOS 向けの分岐（OSPlatform.OSX 等）があります"
fi

# ---------------------------------------------------------------------------
# 4. 共有してよいのは spec/ だけ
# ---------------------------------------------------------------------------
for directory in shared common common-core core-shared; do
  if [ -d "$directory" ]; then
    fail "共有ディレクトリ '$directory' があります（共有してよいのは spec/ のみ）"
  fi
done

# ---------------------------------------------------------------------------
# 5. CI ワークフローのトリガが交差しないこと
# ---------------------------------------------------------------------------
workflows_dir=.github/workflows

check_paths() {
  local file=$1
  local forbidden=$2
  [ -f "$file" ] || return 0
  # コメント行を除いてから判定する（説明文の "apps/macos" を拾わない）
  local hits
  hits=$(grep -v '^[[:space:]]*#' "$file" | grep -n -- "$forbidden" || true)
  if [ -n "$hits" ]; then
    echo "$file:" >&2
    echo "$hits" >&2
    fail "$(basename "$file") のトリガに相手側のパス（$forbidden）が含まれています"
  fi
}

check_paths "$workflows_dir/macos-ci.yml" 'apps/windows'
check_paths "$workflows_dir/windows-ci.yml" 'apps/macos'

# リリースワークフローはファイル名のプラットフォームとタグ接頭辞が一致すること
for file in "$workflows_dir"/release-*.yml; do
  [ -f "$file" ] || continue
  case "$(basename "$file")" in
    release-macos.yml)
      grep -q 'v\*-macos' "$file" || fail "release-macos.yml のタグが v*-macos ではありません"
      if grep -q 'v\*-windows' "$file"; then
        fail "release-macos.yml が Windows のタグを拾っています"
      fi
      ;;
    release-windows.yml)
      grep -q 'v\*-windows' "$file" || fail "release-windows.yml のタグが v*-windows ではありません"
      if grep -q 'v\*-macos' "$file"; then
        fail "release-windows.yml が macOS のタグを拾っています"
      fi
      ;;
  esac
done

# ---------------------------------------------------------------------------
# 結果
# ---------------------------------------------------------------------------
if [ "$failures" -gt 0 ]; then
  echo "" >&2
  echo "プラットフォーム分離の検査に $failures 件の違反があります。" >&2
  echo "方針: 共有してよいのは spec/ のみ。実装は apps/<platform>/ に閉じる（ADR-006）。" >&2
  exit 1
fi

echo "OK: プラットフォーム分離の検査を通過しました。"
