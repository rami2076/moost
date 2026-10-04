# Moost

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)
[![Release](https://img.shields.io/github/v/release/rami2076/moost)](https://github.com/rami2076/moost/releases)

Memo + Roost — AI コーディングエージェント CLI のセッションにメモを付けて記録し、ワンクリックでセッションへ復帰できるシステムトレイ常駐アプリ。

## できること

- **直近セッション一覧**: `claude`/`codex`/`pi` の履歴を自動集約し、最新順に一覧表示
- **ワンクリック復帰**: 一覧の行からターミナルを開いて `--resume` を自動実行
- **メモ**: セッションにタイトル・タグ・本文を付けて記録。元のセッションが
  履歴から消えても、メモからの復帰は機能し続ける
- **登録プロジェクト**: セッション履歴がまだ1件もないディレクトリでも、
  あらかじめ登録しておけば新規セッションをワンクリックで開始できる
- **マルチエージェント対応**: Claude Code / Codex CLI / pi の 3 エージェントに対応
- **セッション要約**: Claude（haiku）/ Codex / pi で直近・全体の要約を取得。書いた
  メモの元セッションに自動で貼り付け
- **MCP 連携**: `moost mcp` を Claude Code / Codex CLI / Claude Desktop の
  MCP サーバーとして登録（JSON-RPC 2.0 over stdio・外部依存なし）
- **アプリ内更新通知**: 新しいバージョンが出ると通知し、Homebrew 導入なら
  ワンクリックで更新できる

## インストール

### macOS（本リリース: v2.0.0-macos）

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

### Linux / Windows

フェーズ D（#73）で native 対応予定（Linux は `v2.0.0-linux`、Windows は
`v2.0.0-windows` として配布予定）。それまでは macOS のみ。

## 構成

```
apps/macos/      Swift/AppKit native アプリ（MoostCore + MoostApp・MCP 内蔵）
packages/core/   リファレンス実装（pure Dart・UI 非依存）
```

## 開発

```bash
cd apps/macos
swift build
swift test
.build/debug/MoostApp --version   # 例: 2.0.0-macos
```

MCP サーバーはアプリに内蔵。CLI から使う場合は:

```bash
.build/debug/MoostApp mcp
```

## ドキュメント

要求・要件・設計資料は docs リポジトリの `project/moost/` を正とする。
リリース手順は [RELEASE.md](./RELEASE.md)。

## ライセンス

[MIT](./LICENSE)
