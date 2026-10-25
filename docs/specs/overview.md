# Moost 紹介

- **リポジトリ**: [rami2076/moost](https://github.com/rami2076/moost)（Public / MIT License）
- **最新バージョン**: v1.10.0（2026-08-15）
- **対応 OS**: macOS（v2.x・実装済み）／Windows（v1.x・フェーズ D で開発中）／Linux（保留）

## 一言でいうと

Memo + Roost（鳥の巣）＝ Moost。Claude Code / Codex CLI のセッションに
メモを付けて記録し、ワンクリックでそのセッションへ復帰できる、
システムトレイ常駐のデスクトップアプリ（macOS / Windows）。

## 解決したい課題

AI コーディングエージェントの CLI（`claude` / `codex`）は、対話ごとに
セッションとして履歴が積み上がっていく。しかしセッション数が増えると、

- 「あのセッション、何の作業だったっけ」を履歴から探すのが大変
- 見つけても `--resume <sessionId>` を手打ちするのが面倒
- そのセッション自体が履歴から消えても、あとで参照したい要点がある

といった困りごとが出てくる。Moost はこれを、**一覧からワンクリックで
復帰**できるようにし、**メモ**という形でセッションに対する人間側の
記録を独立して残せるようにすることで解消する。

## できること

- **直近セッション一覧**: `claude`/`codex` の履歴を自動集約し、最新順に
  一覧表示する。セッションタイトルは各エージェントが生成する ai-title を
  優先し、なければ最終プロンプト先頭 50 文字で代用する
- **ワンクリック復帰**: 一覧の行のターミナルアイコンから、設定した
  ターミナルアプリで復帰コマンド（`cd <project> && claude --resume
  <sessionId>` 等）を自動実行する
- **メモ**: セッションにメモタイトル・タグ・本文を付けて記録する。
  復帰に必要な情報（sessionId・プロジェクトパス）を自己完結で持つため、
  元のセッションが履歴から消えてもメモからの復帰は機能し続ける
- **登録プロジェクト**: セッション履歴がまだ1件もないディレクトリでも、
  あらかじめ登録しておけば新規セッションをワンクリックで開始できる
- **マルチエージェント対応**: Claude Code / Codex CLI の両方に対応。
  直近セッション一覧・メモ一覧はエージェントをまたいで時系列マージし、
  行ごとのバッジで区別する
- **MCP 連携**（v1.9.0〜）: 設定画面からワンクリックで Claude Code /
  Codex CLI / Claude Desktop に MCP サーバーとして登録できる。登録後は
  各エージェント自身から Moost の直近セッション・メモ・登録プロジェクトを
  読み取れる（読み取り専用）
- **アプリ内更新通知と自己修復**（v1.6.0〜 / macOS native v2.1.0〜）: 新バージョンが出ると
  フッターに「アップデート」ボタンを表示し、Homebrew 導入ならアプリ内から更新を実行できる
  （`brew update && brew upgrade --cask moost`）。中断された brew アップグレードで
  インストールが壊れた状態も検知し、同じ場所から修復できる
  （`brew reinstall --cask moost`）。チェックは GitHub Releases のリダイレクト方式
  （設計書 6.8）

## 使い方の流れ

1. Homebrew でインストール（推奨）:
   ```bash
   brew install --cask rami2076/tap/moost
   xattr -dr com.apple.quarantine /Applications/Moost.app
   ```
2. 起動するとメニューバーにトレイアイコンが常駐する（Dock には出ない）
3. トレイアイコンをクリックするとポップオーバーが開き、直近セッション・
   メモ・登録プロジェクトの3タブを切り替えられる
4. セッション行のターミナルアイコンでワンクリック復帰、行タップで
   メモ登録に進める

## 技術構成

```
packages/core/   ロジック層（pure Dart・UI 非依存。history.jsonl 集約、
                 メモ CRUD、復帰コマンド組み立て、要約実行 など）
apps/desktop/    Flutter デスクトップ UI（システムトレイ常駐・
                 tray_manager + window_manager）
apps/mcp_server/ MCP サーバー（読み取り専用、packages/core を再利用）
```

Swift 版の前身アプリ（claude-session-memo）を Dart/Flutter で全面
書き直した後継。macOS App Sandbox は無効化している（`~/.claude/` の
読み取りと `claude`/`codex` サブプロセス起動が必須のため）。

## もっと詳しく知りたいときは

同じ `docs/specs/` 配下に、開発時に参照した資料が揃っている:

- [CONTEXT.md](./CONTEXT.md) — 用語集（「セッション」「メモ」「登録
  プロジェクト」など、本ドキュメントもここでの定義に従っている）
- [requirements.md](./requirements.md) — 要求・要件
- [design.md](./design.md) — 画面設計・アーキテクチャ判断
- [adr/](./adr/) — Architecture Decision Records
- [RELEASE.md](../../RELEASE.md) — リリース手順

外部向けの説明は本体リポジトリの
[README.md](https://github.com/rami2076/moost/blob/main/README.md)、
バージョンごとの変更点は
[CHANGELOG.md](https://github.com/rami2076/moost/blob/main/CHANGELOG.md)
を参照。
