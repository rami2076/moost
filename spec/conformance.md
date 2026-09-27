# Moost 適合検証（Conformance）仕様 — v1 データ契約

> 目的: プラットフォームごとに native 実装しても「同じ製品」でいるための検査項目。
> 各実装（Dart リファレンス / macОS native / 今後の Windows native）は、この文書の
> 全項目と `spec/testdata/` の Fixture を使ったテストに通らなければならない。
> 判断に迷ったら Dart 実装（`packages/core`）の挙動を正とする（リファレンス実装）。

Fixture 実行: `dart test test/spec_conformance_test.dart`（packages/core 内）。
native 実装側は `spec/testdata/` の同一ファイルをそのままテストに使うこと。

## A. JSON 永続基盤（JsonFileStore 相当）

| ID | 項目 | 期待 |
|----|------|------|
| A1 | 書き込みは原子的 | 一時ファイル → 名前変更にことにより、書き込み途中のクラッシュでも本体が壊れない |
| A2 | 破損時の退避 | JSON として読めない既存ファイルは上書きせず `<name>.corrupt-<timestamp>` へ退避し、空として扱う |
| A3 | 読み取りエラーを握りつぶさない | 権限エラー等は例外として伝播する（null 扱いにして上書きし、既存データを失わない） |

## B. `memos.json`（スキーマ: `schemas/memos.schema.json`）

| ID | 項目 | 期待 |
|----|------|------|
| B1 | エンベローラ | `{"schemaVersion": 1, "memos": [...]}`。schemaVersion はアプリ版番号から独立 |
| B2 | 健全な読み込み | Fixture `memos_valid.json` が全 2 件読める。危険文字（バックス・パイプ等）はそのままの値で保持 |
| B3 | 壊れた 1 件の寛容性 | Fixture `memos_corrupt_entry.json` → 健全な 1 件（S-OK）のみ読め、ストア全体は捨てない |
| B4 | メモの不変性 | 編集可は title / tags / body のみ。id / agent / sessionId / projectPath / createdAt は不動（ADR-003） |
| B5 | parseTags | カンマ区切り → trim → 空要素除去（`"a, b ,,c"` → `["a","b","c"]`） |
| B6 | 日付 | UTC ISO8601 文字列。読み込み側は parse できれば許容 |

## C. `settings.json`（スキーマ: `schemas/settings.schema.json`）

| ID | 項目 | 期待 |
|----|------|------|
| C1 | 項目別フォールバック | Fixture `settings_bad_types.json` → 型が違う項目のみデフォルトに戻る（terminalApp=Terminal.app, recentSessionLimit=20, claudePath="", summaryRallyCount=1, copyAnimation=true） |
| C2 | ファイル不在 | デフォルト設定を返す（エラーにしない） |
| C3 | terminalApp を ENUM 化しない | 既知外のアプリ名もそのまま受付ける（Issue #41 の教訓） |
| C4 | ログイン時起動を保存しない | OS 側の実状態（macОS: SMAppService）を正とする |

## D. `projects.json`（スキーマ: `schemas/projects.schema.json`）

| ID | 項目 | 期待 |
|----|------|------|
| D1 | 項目 | `{"schemaVersion": 1, "projects": [{id, projectPath, createdAt}]}` |
| D2 | displayName は導出保存せず | projectPath の最後のディレクトリ名（末尾スラッシュ除去）。抽出不能時 projectPath そのもの |

## E. 直近セッション一覧（`history.jsonl` 読み取り）

Fixture `history.jsonl` に対する期待（excludeMarker = `#MOOST-FORK#`）:

| ID | 項目 | 期待 |
|----|------|------|
| E1 | 壊れた行 / 空行 | JSON で無い行と空行はスキップ（クラッシュしない） |
| E2 | sessionId 集約 | 同 sessionId は最新 timestamp の 1 件に集約。S1 → lastPrompt="second prompt"（2000ms）、S3 → "third prompt"（4000ms） |
| E3 | フォーク除外 | 除外マーカーで始まるプロンプト行は行単位で除外する。マーカー行のみのセッション（Fixture S4）は一覧から消える。通常プロンプトと混在するセッション（S2）は通常側の最新が残る。要約用フォークは全行がマーカーなので結果的にセッションごと消える |
| E4 | timestamp | epoch ミリ秒 → UTC の DateTime |
| E5 | limit | 既定 20 件上限。新しい順 |

## F. 表題と内容

| ID | 項目 | 期待 |
|----|------|------|
| F1 | displayTitle フォールバック | ai-title 無時は lastPrompt の先頭 50 文字（runes 基準。サロゲートペアを分断しない） |
| F2 | ai-title | セッション JSONL の ai-title 行はファイル末尾側 64KB から探す（正: `ai_title_reader.dart` の既存テスト。Fixture 化はフェーズ B で） |

## G. 復帰コマンド

| ID | 項目 | 期待 |
|----|------|------|
| G1 | シェル escape | title・projectPath に バックス / `$` / `;` / `\|` / `&&` / リダイレクトを含んでも、復帰コマンドで注入が作動しない（正: `shell_escape.dart` の既存テスト） |
| G2 | パターン | `cd <project> && <agent> --resume <sessionId>`（agent は claude / codex） |

## H. プラットフォーム受け入れ（Fixture 対象外・native 側で検査）

design.md 7 章の既知を各 native 実装が踏袭していること。

- macОS: GUI 起動で CLI の PATH が通らない問題（ログインシェルから PATH 補完）
- macОS: 外部プロセス stdout/stderr を同時に流さないパイプ詰まり
- macОS: ポップオーバーの hide / キーウィンドウ / イベントタ（design.md 6 章）
- macОS: App Sandbox 制約（Bookmarks / ネットック権限）
- macОS: トレイ常駐（LSUIElement）とログイン時起動
- Windows: トレイ NotifyIcon、単一ファイル publish（フェーズ D）

## 変更手順

- データ契約の変更は MAJOR の製品イベントとして登記する（CHANGELOG に全影響プラ明示）
- `schemaVersion` の上げ下げはこの文書と schemas / testdata の同時変更を必須とする
