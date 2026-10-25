# Windows 版 Moost 実装計画・全体構成（フェーズ D）

- **ステータス**: 進行中（2026-10-25 着手）
- **束ねチケット（EPIC）**: #110
- **決定**: [ADR-006](./adr/006-windows-fully-separated-wpf.md)
- **前提**: macOS native v2.4.0（`apps/macos/`）と同一機能を、**コード共有なし**で実装する

この文書は Windows 案件の**全体構成図と流れ**を 1 枚で把握するための資料である。
仕様の正は [requirements.md](./requirements.md) / [design.md](./design.md) /
[native-migration-plan.md](./native-migration-plan.md)、合格条件の正は
[`spec/conformance.md`](../../spec/conformance.md)。

---

## 1. システム全体像

```mermaid
flowchart LR
  U["ユーザー"] --> T["Moost<br/>タスクトレイ常駐"]
  T --> ST["保存先<br/>%USERPROFILE%\\.moost\\v2<br/>memos / settings / projects"]
  T -->|読み取り専用| AG["エージェントのデータ<br/>.claude / .codex / .hermes"]
  T -->|復帰コマンド| TERM["Windows Terminal<br/>wt.exe / PowerShell"]
  TERM --> CLI["エージェント CLI<br/>claude / codex / pi / hermes"]
  MCPC["MCP クライアント<br/>Claude Code / Claude Desktop"] -->|stdio JSON-RPC 2.0| MCPCMD["moost mcp<br/>（アプリ内蔵サブコマンド）"]
  MCPCMD -->|読み取り専用| ST
  MCPCMD -->|読み取り専用| AG
```

要点:

- Moost は**読み取り専用**。エージェント側データには一切書き込まない
- 復帰は「コマンドを組み立てて端末に渡す」だけで、Moost 自身はセッションを保持しない
- MCP サーバーは**別プロセスを要求しない**（`moost mcp` として同梱）

---

## 2. リポジトリ構成と分離境界

```mermaid
flowchart TB
  subgraph SHARED["共有する唯一の領域（製品契約）"]
    SPEC["spec/<br/>schemas / testdata / conformance.md"]
    DOCS["docs/specs/<br/>仕様書・ADR・本計画"]
  end

  subgraph MAC["apps/macos（Swift / AppKit・変更しない）"]
    MC["MoostCore<br/>ロジック層"]
    MA["MoostApp<br/>AppKit UI"]
  end

  subgraph WIN["apps/windows（C# / WPF・新規）"]
    WC["Moost.Core<br/>ロジック層"]
    WA["Moost.WindowsApp<br/>WPF UI + NotifyIcon"]
    WT["Moost.Core.Tests<br/>xUnit"]
  end

  REF["packages/core（Dart）<br/>参照実装・凍結"]

  SPEC -. "同一 Fixture を使用" .-> WT
  SPEC -. "同一 Fixture を使用" .-> MC
  REF -. "移植の見本" .-> WC
  MC -. "参照のみ・コード共有しない" .-> WC
  MAC -.-|"参照禁止<br/>CI が検査"| WIN
```

分離のルール（CI の分離ゲートで強制）:

| ルール | 検査内容 |
|---|---|
| 言語の非混在 | `apps/macos` に `.cs`、`apps/windows` に `.swift` を置かない |
| 相互参照の禁止 | `apps/macos` から `../windows`、`apps/windows` から `../macos` を参照しない |
| 条件コンパイルの禁止 | `#if os(Windows)` / `#if os(macOS)` / `OS_WINDOWS` を使わない |
| 共有層の限定 | 共有ディレクトリは `spec/` のみ（`shared/` 等を新設しない） |
| ワークフローの非交差 | リリース CI のタグ接頭辞が相手側を拾わない |

---

## 3. Windows アプリのレイヤー構成

```mermaid
flowchart TB
  subgraph UI["Moost.WindowsApp（net10.0-windows）"]
    TRAY["TrayService<br/>NotifyIcon + コンテキストメニュー"]
    POP["PopoverWindow<br/>枠なし・Topmost・Deactivated で隠す"]
    VIEWS["Views<br/>一覧 / メモ / 詳細 / 設定 / 注意"]
    VM["ViewModels<br/>状態とコマンド"]
  end

  subgraph CORE["Moost.Core（net10.0・UI 非依存）"]
    ST["Stores<br/>memos / settings / projects"]
    RD["Readers<br/>claude / codex / pi / hermes"]
    AGG["SessionAggregator<br/>集約・フォーク除外・表題"]
    LG["Launch<br/>復帰コマンド + エスケープ"]
    SM["Summarizer<br/>claude -p / codex exec"]
    PD["AgentPathDetect<br/>CLI パス解決"]
    MCPS["MCPServer<br/>読取り専用 4 ツール"]
  end

  subgraph OS["OS 資源（P/Invoke または .NET API）"]
    FS["FileSystem"]
    PR["Process"]
    SQ["SQLite<br/>Microsoft.Data.Sqlite"]
    RG["レジストリ<br/>HKCU\\...\\Run"]
    NI["Shell_NotifyIcon"]
  end

  TRAY --> NI
  TRAY --> POP
  POP --> VIEWS
  VIEWS --> VM
  VM --> ST
  VM --> RD
  VM --> LG
  VM --> SM
  VM --> MCPS
  RD --> AGG
  RD --> FS
  SM --> PD
  SM --> PR
  RD --> SQ
  ST --> FS
  VIEWS --> RG
```

依存方向は **UI → Core → OS** の一方通行。`Moost.Core` は WPF を参照しない
（macOS の「Core は AppKit/SwiftUI を import しない」という性質の写像）。

---

## 4. データフロー: 直近セッション一覧

```mermaid
sequenceDiagram
  autonumber
  participant U as ユーザー
  participant TR as TrayService
  participant VM as ViewModel
  participant RD as Readers
  participant FS as ファイル / SQLite
  participant AG as SessionAggregator

  U->>TR: トレイアイコンをクリック
  TR->>TR: ポップオーバーをカーソル側の画面に配置
  TR->>VM: 表示（再読込のトリガ）
  VM->>RD: readRecentSessions(limit)
  RD->>FS: .claude\\history.jsonl
  RD->>FS: .codex\\history.jsonl + rollout
  RD->>FS: .hermes\\state.db（読み取り専用）
  FS-->>RD: 生レコード
  RD->>AG: 集約を依頼
  AG->>AG: sessionId 単位で最新を採用<br/>フォーク除外（#MOOST-FORK#）<br/>ai-title 末尾 64KB 逆走査<br/>無ければ先頭 50 文字
  AG-->>VM: List<Session>
  VM-->>U: 一覧を表示（新しい順・上限 20 件）
```

---

## 5. 復帰フロー（ワンクリック復帰）

```mermaid
sequenceDiagram
  autonumber
  participant U as ユーザー
  participant VM as ViewModel
  participant LG as Launch
  participant CB as クリップボード
  participant WT as Windows Terminal

  U->>VM: 「ターミナルで再開」
  VM->>LG: buildResume(agent, projectPath, sessionId)
  LG->>LG: PowerShell 方式でエスケープ<br/>（'...' の内側の ' は '' に）
  LG-->>VM: cd '<project>' && claude --resume '<id>'
  VM->>CB: コピー（コピー操作時）
  VM->>WT: wt.exe で新規ウィンドウを開きコマンドを実行
  WT->>WT: PowerShell を起動して cd → --resume
  Note over LG,WT: Windows Terminal が無ければ PowerShell 単体へフォールバック
```

危険文字（`$` `;` `|` `&&` `>` バッククォート `'` `\` 空白）を含むパスでも
コマンドが壊れず、注入も成立しないことをテストで担保する（conformance G1）。

---

## 6. UI 状態遷移（常駐アプリの振る舞い）

```mermaid
stateDiagram-v2
  [*] --> TrayOnly: 起動（ウィンドウは出さない）
  TrayOnly --> Shown: トレイ左クリック
  Shown --> TrayOnly: フォーカス喪失（Deactivated）
  Shown --> TrayOnly: トレイ再クリック
  Shown --> TrayOnly: 閉じる操作（終了しない）
  TrayOnly --> [*]: メニュー「終了」

  state Shown {
    [*] --> List
    List --> MemoForm: メモ登録 / 編集
    List --> SessionDetail: 行を選択
    SessionDetail --> MemoForm: 要点をメモへ
    MemoForm --> SessionDetail: 詳細へ戻る
    List --> Settings: 設定
    List --> Notice: 注意画面
    Settings --> List: 戻る
    Notice --> List: 戻る
  }
```

macOS の NSPopover と同じく「アプリ外を触ると隠れる」。トレイクリック直後の
blur → hide の競合（design.md 7 章のハマりどころ）にはガードを入れる。

---

## 7. リリースフロー（プラットフォーム完全分離）

```mermaid
flowchart LR
  TAGW["タグ push<br/>v1.0.3-windows"] --> RW["release-windows.yml<br/>(windows-latest)"]
  TAGM["タグ push<br/>v2.4.1-macos"] --> RM["release-macos.yml<br/>(macos-latest)"]

  RW --> PUB["dotnet publish<br/>-r win-x64 --self-contained<br/>PublishSingleFile"]
  PUB --> ZIP["Moost-1.0.3-windows.zip"]
  ZIP --> RELW["GitHub Release<br/>（Windows）"]
  RELW --> WG["winget manifest PR<br/>InstallerType: zip + portable"]
  WG --> WGU["winget install / upgrade"]

  RM --> DMG["Moost-2.4.1-macos.dmg"]
  DMG --> RELM["GitHub Release<br/>（macOS）"]
  RELM --> CASK["homebrew-tap の cask bump"]

  RW -. "交差しない（トリガで保証）" .- RM
```

バージョンの写像:

| タグ | 成果物 | winget `PackageVersion` | cask `version` |
|---|---|---|---|
| `v1.0.3-windows` | `Moost-1.0.3-windows.zip` | `1.0.3`（接尾辞なし） | — |
| `v2.4.1-macos` | `Moost-2.4.1-macos.dmg` | — | `2.4.1-macos` |

---

## 8. CI の分離とゲート

```mermaid
flowchart TB
  PR["Pull Request"] --> CH{"変更されたパス"}

  CH -->|"apps/windows/**"| WCI["windows-ci.yml<br/>dotnet build + test"]
  CH -->|"apps/macos/**"| MCI["macos-ci.yml<br/>swift build + test"]
  CH -->|"spec/**"| BOTH["windows-ci と macos-ci の両方<br/>（契約変更は全実装に影響）"]
  CH -->|"その他"| CI["ci.yml<br/>core / desktop / mcp_server / osv-scan"]

  WCI --> SEP["separation gate<br/>参照・条件コンパイル・共有層の検査"]
  MCI --> SEP
  SEP -->|"混入を検出"| NG["fail（マージ不可）"]
  SEP -->|"問題なし"| OK["マージ可"]
```

「片方の変更で両方が走る」状態を避けることが目的。例外は `spec/**` のみで、
これは**意図的な交差**（データ契約の変更は全実装に影響するため）。

---

## 9. conformance ゲート（言語に依存しない合格条件）

```mermaid
flowchart LR
  SPEC["spec/conformance.md<br/>26 項目 + testdata"]
  SPEC --> T1["Dart 参照実装<br/>spec_conformance_test.dart"]
  SPEC --> T2["macOS native<br/>SpecConformanceTests.swift"]
  SPEC --> T3["Windows native<br/>Moost.Core.Tests（xUnit）"]
  T3 --> G{"全項目が緑か"}
  G -->|"yes"| REL["そのプラットフォームはリリース可"]
  G -->|"no"| STOP["リリース不可（CI で強制）"]
```

項目の内訳: A（JSON 永続 3）・B（memos 6）・C（settings 4）・D（projects 2）・
E（一覧 7）・F（表題 2）・G（復帰 2）＋ H（プラットフォーム受け入れ）。

---

## 10. データ配置

```mermaid
flowchart LR
  HOME["%USERPROFILE%"] --> M1[".moost\\v2\\memos.json"]
  HOME --> M2[".moost\\v2\\settings.json"]
  HOME --> M3[".moost\\v2\\projects.json"]
  HOME --> A1[".claude\\history.jsonl<br/>.claude\\projects\\**"]
  HOME --> A2[".codex\\history.jsonl<br/>.codex\\sessions\\**"]
  HOME --> A3[".hermes\\state.db<br/>（SQLite・読み取り専用）"]
  HOME --> A4["pi のセッション履歴<br/>（実機で確認）"]
```

- 保存先は `%USERPROFILE%\.moost\v2\`（macOS の `~/.moost/v2/` に対応）
- **Windows には旧版データが無いため v1 → v2 移行は不要**
- アンインストールしてもメモは残る（`.moost` は消さない）

---

## 11. タスク依存（チケット）

```mermaid
flowchart TB
  A["#96 ADR-006"] --> B["#97 骨組み + windows-ci"]
  B --> C["#98 永続層（A–D）"]
  C --> D["#99 一覧・表題（E–F）"]
  C --> E["#100 復帰コマンド・escape（G）"]
  D --> F["#101 readers・パス検出・要約"]
  D --> I["#104 moost mcp"]
  B --> G["#102 トレイ常駐"]
  E --> H["#103 画面一式・復帰起動"]
  G --> H
  A --> J["#105 CI 分離・分離ゲート"]
  B --> J
  B --> K["#106 リリース CI 分離"]
  H --> N["#108 更新チェック"]
  K --> N
  A --> L["#107 リリース資料・更新漏れ検出"]
  M["#109 Scoop（不採用・close）"]
```

---

## 12. リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| 各エージェントの Windows 実パスが未検証 | 一覧が空になる | #101 の着手時に実機で最初に確認する |
| Hermes の SQLite 読み取り | 一覧・抜粋が出ない | `Microsoft.Data.Sqlite` を追加（クールダウン 7 日 + osv-scanner を通す） |
| 要約のサブプロセスがハング | UI が固まる | stdout/stderr の同時読み・タイムアウト・キャンセル |
| 二重保守のドリフト | macOS と挙動が違う | conformance をリリースゲートにする（#105）／`spec/` 先行更新 |
| winget の検証待ち | 「出した瞬間に入らない」 | zip が即時性を担保（#106） |
| SmartScreen 警告（ブラウザ経由 DL） | 導入の離脱 | README に回避手順を明記（#107） |
| 分離の形骸化 | 時間とともに混ざる | 分離ゲートで機械的に強制（#105） |
