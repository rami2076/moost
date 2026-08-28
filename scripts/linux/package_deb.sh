#!/usr/bin/env bash
# Moost を Ubuntu/Debian 向けの .deb にパッケージングする（Q1）。
#
# 使い方:
#   apps/desktop で `flutter build linux --release` を実行後、
#   packages/core は無関係。mcp_server の moost-mcp バイナリをバンドルへ
#   コピーしておくこと（release.yml が行う）。
#
#   本スクリプトは repo ルートで実行する想定。
#   ./scripts/linux/package_deb.sh
#
# 生成物: dist/moost_<version>_amd64.deb（または arm64）
set -euo pipefail

# --- リポジトリルートへ移動 ---
cd "$(cd "$(dirname "$0")/../.." && pwd)"

# --- アーキテクチャ判定 ---
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64; BUNDLE_ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64; BUNDLE_ARCH=arm64 ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

# --- バージョン (pubspec.yaml の version 行から) ---
VERSION_LINE=$(grep -E '^version:' apps/desktop/pubspec.yaml | head -1)
VERSION=$(echo "$VERSION_LINE" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?.*/\1/')
echo "Packaging moost $VERSION ($ARCH)"

BUNDLE="apps/desktop/build/linux/${BUNDLE_ARCH}/release/bundle"
if [ ! -x "$BUNDLE/moost_desktop" ]; then
  echo "bundle not found: $BUNDLE" >&2
  echo "Run: (cd apps/desktop && flutter build linux --release)" >&2
  exit 1
fi

PKG_NAME="moost_${VERSION}_${ARCH}"
STAGE="dist/${PKG_NAME}"

# --- クリーンアップ ---
rm -rf "$STAGE" "dist/${PKG_NAME}.deb"

# --- インストール構成:
#   /opt/moost/       アプリ本体（実行ファイル + lib + data）
#   /usr/share/applications/moost.desktop
#   /usr/share/icons/hicolor/.../moost.png  (256px のみ)
#   /usr/bin/moost    → /opt/moost/moost_desktop への symlink
OPT="/opt/moost"
mkdir -p "$STAGE/$OPT"
cp -R "$BUNDLE"/. "$STAGE/$OPT/"
chmod +x "$STAGE/$OPT/moost_desktop"

# MCP バイナリが同梱されていればそのまま（release.yml がコピー済みを想定）
if [ ! -x "$STAGE/$OPT/moost-mcp" ]; then
  echo "warning: moost-mcp not found in bundle; skipping (dev build)" >&2
fi

# バイナリ名はランチャー（TerminalLauncher）と整合させる。deb ではシンボリックリンクを張る
# （/opt/moost/moost_desktop を直接起動するのが本命。/usr/bin/moost は便宜のエイリアス）
mkdir -p "$STAGE/usr/bin"
ln -s "$OPT/moost_desktop" "$STAGE/usr/bin/moost"

# .desktop エントリ
mkdir -p "$STAGE/usr/share/applications"
cat > "$STAGE/usr/share/applications/moost.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Moost
Comment=Attach memos to AI coding agent sessions and resume them from the system tray
Exec=$OPT/moost_desktop
Icon=moost
Terminal=false
Categories=Utility;
StartupNotify=false
EOF

# アイコン (tray_icon.png をアプリアイコンとして流用)
mkdir -p "$STAGE/usr/share/icons/hicolor/256x256/apps"
cp apps/desktop/assets/tray_icon.png "$STAGE/usr/share/icons/hicolor/256x256/apps/moost.png"

# --- DEBIAN/control ---
mkdir -p "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: moost
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: rami2076 <sakusennx@gmail.com>
Depends: libgtk-3-0, libayatana-appindicator3-1, libnotify4, xdg-utils
Description: Attach memos to AI coding agent sessions and resume them from the system tray
 Memo + Roost. A system tray resident app for AI coding agent CLI sessions
 (Claude Code / Codex CLI) on Linux/Ubuntu.
EOF

cat > "$STAGE/DEBIAN/conffiles" <<EOF
EOF
rm -f "$STAGE/DEBIAN/conffiles"

# /opt/moost 内の不要な中間物は使わない
rm -rf "$STAGE/$OPT/intermediates_do_not_run" 2>/dev/null || true

# パーミッション整理（deb は root 所有が望ましいが、ビルド環境の uid のままにし、
# dpkg-deb はマウント権限に依存しないため、= <same> で問題にならない）
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/$OPT/moost_desktop" "$STAGE/usr/bin/moost" 2>/dev/null || true
chmod 755 "$STAGE/$OPT/moost-mcp" 2>/dev/null || true
find "$STAGE/$OPT/lib" -type f -exec chmod 644 {} +
find "$STAGE/$OPT" -maxdepth 1 -type f -name 'moost_desktop' -exec chmod 755 {} +

# --- .deb 生成 ---
dpkg-deb --build --root-owner-group "$STAGE" "dist/${PKG_NAME}.deb"
echo "created dist/${PKG_NAME}.deb"
ls -lh "dist/${PKG_NAME}.deb"
