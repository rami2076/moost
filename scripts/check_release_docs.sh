#!/usr/bin/env bash
#
# リリース資料の整合性チェック（#107）
#
# リリースのたびに更新が必要な資料が、実装とズレていないかを機械的に確かめる。
# 「人がチェックリストを目で追う」依存を減らすのが目的。
#
# 検査項目:
#   1. CHANGELOG にプラットフォーム別の見出しがある（## macOS / ## Windows）
#   2. バージョンをコードに二重管理していない（apps/windows に <Version> を書かない）
#   3. README に Windows の導入手順（winget）がある
#   4. release.md に Windows のリリース手順（7 章）とチェックリストがある
#   5. 機能サポートマトリクス（native-migration-plan.md 7.3）が存在する
#
# 使い方: bash scripts/check_release_docs.sh
set -uo pipefail

failures=0

fail() {
  echo "NG: $*" >&2
  failures=$((failures + 1))
}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root" || exit 1

# 1. CHANGELOG のプラットフォーム別ヘッダ
grep -q '^## macOS ' CHANGELOG.md || fail "CHANGELOG に「## macOS <semver>」の見出しがありません"
grep -q '^## Windows ' CHANGELOG.md || fail "CHANGELOG に「## Windows <semver>」の見出しがありません"

# 2. バージョンの二重管理の禁止（タグから CI が注入する）
if grep -rnE '<Version>[^<]+</Version>' --include='*.csproj' --include='*.props' apps/windows 2>/dev/null | grep -q .; then
  fail "apps/windows に <Version> が直書きされています（版番号はタグから注入する）"
fi
if ! grep -q '<VersionPrefix>0\.0\.0</VersionPrefix>' apps/windows/Directory.Build.props; then
  fail "Directory.Build.props の VersionPrefix が 0.0.0 ではありません（版番号はタグから注入する）"
fi

# 3. README の Windows 導入手順
grep -q 'winget install --id rami2076.Moost' README.md \
  || fail "README に winget の導入手順がありません"

# 4. release.md の Windows 手順とチェックリスト
grep -q '^## 7\. ' RELEASE.md || fail "release.md に 7 章（Windows のリリース手順）がありません"
grep -q 'リリース前チェックリスト' RELEASE.md \
  || fail "release.md に「リリース前チェックリスト」がありません"

# 5. 機能サポートマトリクス
grep -q '^### 7\.3 機能サポートマトリクス' docs/specs/native-migration-plan.md \
  || fail "native-migration-plan.md に 7.3 機能サポートマトリクスがありません"

if [ "$failures" -gt 0 ]; then
  echo "" >&2
  echo "リリース資料の整合性チェックに $failures 件の不足があります（#107）。" >&2
  exit 1
fi

echo "OK: リリース資料の整合性チェックを通過しました。"
