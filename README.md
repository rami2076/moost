# Moost

Memo + Roost — AI コーディングエージェント CLI（まず Claude Code）のセッションにメモを付けて記録し、ワンクリックでセッションへ復帰できるシステムトレイ常駐アプリ。

## インストール（macOS）

### Homebrew（推奨）

```bash
brew install --cask rami2076/tap/moost
xattr -dr com.apple.quarantine /Applications/Moost.app
```

更新は `brew upgrade` で入る。2 行目は ad-hoc 署名による Gatekeeper 警告の
回避（brew はダウンロードに quarantine 属性を付けるため）。

### gh CLI

各 [Release](https://github.com/rami2076/moost/releases) のノートに
コピペで動くインストールコマンドを記載している（quarantine が付かないため
Gatekeeper 警告なしで起動できる）。

### 手動ダウンロード

[Releases](https://github.com/rami2076/moost/releases) から dmg をダウンロードし、
`Moost.app` を Applications へドラッグする。

> **初回起動時の注意**: 当面 ad-hoc 署名のため Gatekeeper の警告が出る。
> Finder で `Moost.app` を右クリック →「開く」を選ぶと以後は起動できる。

## 構成

```
packages/core/   ロジック層（pure Dart・UI 非依存）
apps/desktop/    Flutter デスクトップ UI（フェーズ 2）
```

## 開発

```bash
cd packages/core
dart pub get
dart test
dart run bin/moost.dart --help   # CLI サンプル
```

## ドキュメント

要求・要件・設計資料は docs リポジトリの `project/moost/` を正とする。
リリース手順は [RELEASE.md](./RELEASE.md)。

## ライセンス

[MIT](./LICENSE)
