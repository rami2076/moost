# Changelog

形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う。

## [Unreleased]

### Added

- 設定に「コピー成功アニメーション」の ON/OFF を追加（`settings.json` に永続化）

### Changed

- コピー操作（復帰コマンド・セッション ID・更新コマンド）の成功表示を、
  スナックバーのメッセージから「円周を緑の線が一周 → アイコンが緑のチェックマークに変わる」方式へ変更

## [1.4.0] - 2026-07-20

### Added

- アプリ内更新通知（#12）: 新しいバージョンがあるとフッターに「vX.Y.Z が利用可能」を表示。
  brew 導入なら更新コマンドをコピー、手動導入ならリリースページを開く。
  チェックは GitHub の `releases/latest` リダイレクト方式（レート制限なし・失敗時は沈黙）

## [1.3.0] - 2026-07-19

### Added

- Homebrew tap（`rami2076/tap`）で配信。release.yml がリリース時に cask を自動 bump（#11）

### Fixed

- マルチディスプレイ: 拡張ディスプレイのトレイアイコンをクリックしても主ディスプレイ側に
  ポップオーバーが開いていた。クリック位置のあるディスプレイのメニューバー直下に開くよう修正（#16）

## [1.2.0] - 2026-07-16

### Added

- apps/desktop: セッション一覧・メモ一覧の各行に最終利用/更新日時を表示（サブタイトル行の右端）
- apps/desktop: メモ一覧の各行にゴミ箱アイコンを追加。押した行だけが確認表示
  （「〈タイトル〉を削除しますか？」+ キャンセル / 削除）に置き換わり、その場で削除できる

## [1.1.0] - 2026-07-16

### Added

- Codex CLI 対応（AgentAdapter の第 2 実装）
  - packages/core: CodexAdapter（`~/.codex/history.jsonl` 集約 + rollout JSONL の
    `session_meta.cwd` でプロジェクトパス補完、`codex resume` 復帰、
    `codex exec --ephemeral` 要約（直近抜粋 / `exec resume` 全体の 2 モード））
  - packages/core: AdapterRegistry（複数エージェントの直近セッションを時系列マージ、
    agentId による adapter ルーティング）
  - apps/desktop: 統合リスト + エージェントバッジ（セッション / メモの両タブ）、
    セッション詳細にエージェント行、要約ボタンをエージェント名表示に

## [1.0.0] - 2026-07-16

Dart/Flutter 版の初回リリース（Swift 版 claude-session-memo 1.0.4 の後継）。

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
