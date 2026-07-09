# Changelog

形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う。

## [Unreleased]

### Added

- packages/core: フェーズ 1 の初期実装
  - 直近セッション一覧の取得（history.jsonl 集約 + ai-title 末尾走査）
  - メモ CRUD（`~/.moost/v1/memos.json`、アトミック書き込み・破損時退避）
  - 復帰コマンドの組み立て（シェルエスケープ込み）
  - セッション要約（`claude -p`、直近 N ラリー抜粋 / 全体 fork の 2 モード）
  - SummaryCache（メモリのみ）/ TerminalLauncher（osascript）
  - CLI サンプル（一覧表示・メモ登録・復帰コマンド出力）
- apps/desktop: フェーズ 2 の macOS デスクトップ UI
  - 一覧（直近セッション / メモの 2 タブ、自動再読込）
  - メモ登録・編集フォーム（タイトル初期値 = セッションタイトル、インライン削除確認）
  - セッション詳細 + 要約実行（範囲切替・ラリー数ステッパー・キャッシュ）
  - 設定（ターミナル種別・表示件数・claude パス）/ 注意画面 / フッター
  - ターミナル起動（Terminal.app / iTerm2）
  - システムトレイ常駐（tray_manager + window_manager、LSUIElement で Dock 非表示）
  - i18n（日英、gen_l10n）

### Changed

- macOS の App Sandbox を無効化（`~/.claude/` 読み取りと claude サブプロセス起動に必須）
