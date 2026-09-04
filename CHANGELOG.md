# Changelog

形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う。

## [Unreleased]

### Fixed

- **Issue #68: pi セッションの再開・新規作成でモデル 404 になる問題**:
  pi は起動時に現在の既定 model/provider を使うため、セッションが使っていた
  ローカルモデルがサーバーで配信されていないと再開・新規作成とも最初の
  やり取りで 404 になるのを、設定画面から pi の provider / model を指定して
  `pi --provider <p> --model <m>` で起動できるようにして回避。
  設定はアプリ再起動後に反映（PiAdapter は起動時に構築されるため）。

## [1.11.0] - 2026-09-03

### Added (Linux / Ubuntu)

- **Linux (Ubuntu 24.04) 対応**: Flutter Linux デスクトップビルドを追加し、
  `.deb` パッケージ（`scripts/linux/package_deb.sh`）をリリースに自動添付するように
  （Q1）。`.deb` は `/opt/moost/` に展開し、ランチャーのデスクトップエントリと
  `moost` コマンドのシンボリックリンクを用意
- **トレイ常駐**: AppIndicator 経由。Ubuntu 標準の GNOME では既定で有効。
  拡張がない環境では通常ウィンドウとして動作するフォールバックを実装（Q4）
- **復帰先ターミナル**: 設定に `gnome-terminal` を追加。Linux では
  gnome-terminal（無ければ `x-terminal-emulator`）を bash ログインシェルで起動し
  復帰コマンドを実行（Q3）。macOS 専用ターミナル値（Terminal.app / iTerm2）が
  設定に残っていても gnome-terminal へ正規化
- **PATH 自動検出の Linux 対応**: `claude`/`codex` のパス解決を macOS の
  zsh に加えて Linux では bash（`-ic`）で行うように
- **更新通知の Linux 対応**: brew のない環境ではリリースページを開く手動導線に。
  `xdg-open` を利用。InstallHealthChecker（macOS cask 固有）は Linux では
  無効
- **MCP 連携の Linux 対応**: Claude Desktop 設定パスを Linux では
  `~/.config/Claude/claude_desktop_config.json` に。同梱 moost-mcp バイナリの
  配置先も Linux バンドルに合わせて解決
- **Linux の日本語表示修正**: Flutter Linux エンジンは既定フォント族から CJK へ
  fallback せず豆腐（□）化するため、ThemeData の fontFamilyFallback に
  Noto Sans CJK JP / Yu Gothic / Hiragino 等を明示指定（macOS は上書きなし）
- **Linux のトレイ体験改善**: (1) ダークパネルで見えるよう白版アイコン
  （tray_icon_white.png）を Linux で使用、(2) blur での自動非表示を Linux では
  やめ、メニュー経由の「開く」でウィンドウが一瞬で隠れる問題を解消
  - 起動時はトレイだけ・ウィンドウ非表示（runner の first_frame 自動表示を
    no-op 化。自動表示が起動時に出る真因だった）
  - 表示位置は**トレイアイコンの直下**（Linux は setPosition 非対応のため
    setBounds でカーソル直下に配置）
- **Linux のトレイクリック動作を「標準の 2 アクション起動」に整理**: 
  シングルクリック=メニュー表示、メニューの「Open Moost」で開く（既定）。
  小細工（XRecord/XTest 合成・ESC 自動クローズ）は設定
  `trayClickMode`（Linux のみ設定画面で選択）で有効化できる選択肢に:
  - なし（既定）: シングルクリックはメニューのみ（AboutToShow で
    ウィンドウを勝手に開かない）。メニューの「Open Moost」で開く
  - A(fakeDouble): XRecord でトレイ領域の 1 クリックを検知し XTest で
    2 発目を合成して「ダブル扱い」に → メニューなしで直接開く
  - B(closeMenu): 開いた直後にメニューへ ESC を送って自動クローズ
  - ビルド依存に libxtst-dev を追加（release.yml も追記）
- **NVIDIA EGL/GLX 環境での Flutter 描画クラッシュ対策**: ランナー
  （main.cc）で Flutter engine をソフトウェアレンダリング
  （`FLUTTER_ENGINE_SWITCHES=--enable-software-rendering`）に設定。
  一部の NVIDIA ドライバでウィンドウ表示時の描画スレッドが
  libnvidia-*core.so 内で SIGSEGV する問題を回避（環境変数があれば尊重）
- **pi エージェント対応**: pi（この coding agent）のセッション
  （`~/.pi/agent/sessions/**/*.jsonl`）を直近一覧・メモ・復帰の対象に追加。
  復帰は `pi --session <id>`、要約はローカル抽出（API 消費なし）。
  MCP サーバー側も pi を追加

## [1.10.0] - 2026-08-15

### Added

- 中断された brew アップグレードでインストールが壊れた状態（Caskroom に
  `*.upgrading` の中間ディレクトリが残り `/Applications/Moost.app` が
  空になる等）を起動時に検知し、フッターのアップデートボタンと同じ場所に
  「修復」ボタンを表示するように（#58）。`brew reinstall --cask moost`
  を実行し、空になったアプリが邪魔で失敗する場合は取り除いて自動的に
  再試行する
- アップデート/修復の失敗時、エラーメッセージをクリップボードへ
  コピーできるボタンを追加（#58）

### Fixed

- `claude`/`codex` の PATH 自動検出が、`.zshrc` 経由で PATH を追加する
  環境（nvm/pyenv/asdf 等）では最小 PATH のアプリ起動時に見つからないこと
  があった問題を修正（#53）。ログインシェル解決を `zsh -lc` から
  `zsh -lic`（対話シェル）に変更し、`.zshrc` まで読み込むようにした。
  あわせて、対話シェル化によって `.zshrc` 自体の出力が標準出力に混ざる
  ケースに備え、実行結果は標準出力の最終行のみを採用するようにした

## [1.9.1] - 2026-08-15

### Fixed

- Moost 自身のプロセスが Claude Code 由来の環境変数
  （`CLAUDE_CODE_CHILD_SESSION` 等）を保持していると、要約用の `claude -p`
  や、復帰・新規セッション開始でターミナルへ渡すコマンドにそのまま
  引き継がれ、開始したセッションが「子セッション」と誤認識されて
  transcript が保存されなくなることがあった問題を修正（#52）。除去対象は
  `CLAUDE_` プレフィックスの変数を広く判定する方式にし、固定リストに
  ない新しい変数（例: `CLAUDE_PID`）にも追従できるようにした

## [1.9.0] - 2026-08-15

### Added

- 設定画面から MCP 連携をワンクリックで登録・解除できるように（#45）:
  Claude Code / Codex CLI は `mcp add`/`mcp remove` を内部的に実行、
  Claude Desktop は `claude_desktop_config.json` の `mcpServers` を安全に
  マージ更新する。連携済みの相手は行ごとに「連携済み」表示＋解除ボタンに
  切り替わり、誤って再登録することもない。連携状態の確認は外部プロセス
  起動を伴い遅いため、設定画面本体の表示とは切り離して非同期に反映する。
  同梱バイナリ（`moost-mcp`）を Moost.app に追加し、Homebrew cask からも
  `moost-mcp` として直接呼べるようにした
- （開発者向け）設定画面のデバッグ欄に、`moost-mcp` バイナリ自体の
  自己診断（`initialize` ハンドシェイクの疎通確認）を追加

## [1.8.0] - 2026-07-27

### Added

- MCP サーバー対応（読み取り専用）（#43）: Claude Desktop / Claude Code 等の
  MCP ホストから、直近セッション・メモ・登録プロジェクトを読み取れる新パッケージ
  `apps/mcp_server` を追加。誤書き換えリスクを避けるため v1 は読み取り専用の
  4 ツール（`list_recent_sessions` / `list_memos` / `list_registered_projects` /
  `get_resume_command`）のみ。`packages/core` の既存ロジックをそのまま再利用

## [1.7.1] - 2026-07-23

### Fixed

- 直近セッション一覧・メモ一覧・プロジェクト一覧の3タブとも、素の一覧だと
  スクロール可能なことが見た目で分からなかったため、常時表示のスクロール
  バーを追加した

## [1.7.0] - 2026-07-23

### Added

- 登録プロジェクト機能（#28）: セッション履歴が1件もないディレクトリでも、
  明示的に登録しておけば新規セッションをワンクリックで開始できる。
  「プロジェクト」タブの一覧上部の「登録」ボタンから OS のフォルダ選択
  ダイアログでディレクトリを選ぶ。各行にエージェント（Claude Code / Codex）
  ごとの起動ボタンを並べ、エージェントは登録時ではなく起動時に選ぶ（ADR-004）。
  エージェント別の起動アイコンは各社公式サイトの配色（Claude: `#D97757`、
  Codex: `#6867AA`）で色分け（商標ロゴは無提携の第三者アプリでは
  使用できないため）。削除（登録解除）はメモと同じインライン確認 UI
- プロジェクトタブの一覧上部に、登録の意味を説明するキャプションを追加

### Changed

- フォルダ選択ダイアログを osascript 経由から `file_selector` パッケージに
  切り替え。macOS では `NSOpenPanel` をポップオーバー自身のウィンドウへ
  シート表示するため、ダイアログ表示中にポップオーバーがフォーカスを失って
  隠れることがなくなった

### Fixed

- フォルダ選択ダイアログを開いている間に別アプリを操作すると、ポップオーバーが
  隠れてしまい、かつネイティブ側のダイアログの状態が壊れて次回以降ダイアログが
  開かなくなる（システムのビープ音のみが鳴る）不具合を修正。ダイアログ表示中は
  ポップオーバーを隠す全ての経路（フォーカス喪失・トレイアイコンのトグル・
  ウィンドウを閉じる操作）で自動非表示を止めるようにした

## [1.6.1] - 2026-07-20

### Added

- MIT ライセンスを追加（`LICENSE`、README にリンク）

## [1.6.0] - 2026-07-20

### Added

- 設定画面の見出し直下にアプリバージョンを常時表示（アップデートが実際に
  反映されたか一目で分かるように）

### Changed

- フッターの更新ボタンを、コマンドをコピーするだけの UI から実際に更新できる
  フローに変更。ボタン自体が丸い確認ピル（「アップデートしますか? はい/いいえ」）に
  変化し、「はい」で brew 導入時は `brew update && brew upgrade --cask moost` を
  アプリが実際に実行（進捗は不確定インジケーター。brew の CLI 出力に数値の進捗が
  ないため）→ 完了で「再起動」ボタンを表示し、手動クリックで新版を起動する
  （自動再起動はしない）。手動導入の場合はこれまでどおりリリースページを開くのみ。
  「いいえ」を選ぶと、自動実行の代わりにコマンドをコピーするか尋ねる導線があり、
  コピー後は同じピルの中で「コピーしました」を表示してから自動で最初に戻る
  （表示時間はデバッグビルドで ms 単位に調整可能）
- フッターの終了ボタンを設定画面へ移動（更新ボタンの確認 UI と幅を取り合わないように）
- リリースノートのインストール手順を簡略化。Homebrew 利用者は `brew upgrade --cask moost`
  の1行、非利用者は dmg をダウンロードして `open` するだけ（あとは通常どおり
  Applications へドラッグ）。`hdiutil`/`cp -R` での直接上書きは廃止

## [1.5.0] - 2026-07-20

### Added

- 設定に「コピー成功アニメーション」の ON/OFF を追加（`settings.json` に永続化）

### Changed

- コピー操作（復帰コマンド・セッション ID・更新コマンド）の成功表示を、
  スナックバーのメッセージから「円周を緑の線が一周 → アイコンが緑のチェックマークに変わる」方式へ変更
- コピー操作のフィードバック表示中（スイープ・チェック保持中）は連打で
  再トリガーされないようボタンを一時的に無効化

### Fixed

- 上記の連打対策で `onPressed: null` を使っていたため、フィードバック表示中に
  アイコンを叩くとタップが親の行（ListTile）へ素通りしてメモ登録/編集画面へ
  誤遷移していた。ハンドラは常に渡し、busy 判定は内部で行うよう修正

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
