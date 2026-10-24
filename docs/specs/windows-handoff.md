# Windows 版 Moost 開発の引き継ぎ（フェーズ D）

Windows PC の別セッションで Windows 版の開発・リリースを進めるための入口。
macOS 側（v2.4.0-macos まで）の実装を前提に、**共通ロジックと仕様は再利用**する。

## 1. まず読む順

1. [overview.md](./overview.md) — 全体像・用語・リポジトリ構成
2. [requirements.md](./requirements.md) — 要求・要件（データ契約）
3. [design.md](./design.md) — 画面設計・アーキテクチャ判断・ハマりどころ
4. [native-migration-plan.md](./native-migration-plan.md) — フェーズ D（7.3・詳細版 A）
5. [RELEASE.md](../../RELEASE.md) — 7 章が Windows のリリース基盤
6. `spec/conformance.md` と `spec/testdata/` — 実装が満たすべき検証項目

## 2. 現状（2026-10-24）

| 項目 | 状態 |
|---|---|
| MoostCore（ロジック層） | ✅ **Windows でビルド・テスト可能**（Foundation のみ。SQLite3 / CoreGraphics は条件コンパイル） |
| CI `windows-core` | ✅ **green**（`windows-latest` + Swift 6.4.1 で `swift build` / `swift test`） |
| MoostApp（トレイ UI） | ❌ macOS 専用（AppKit / SwiftUI）。**Windows 用 UI は未実装** |
| Windows リリース | ❌ 未着手（タグ規約・成果物は RELEASE.md 7.2 に計画） |

## 3. 環境セットアップ（Windows）

1. **Swift for Windows**（公式インストーラ）を入れる
   - https://www.swift.org/install/windows/
   - Visual Studio 2022 Build Tools（C++ ワークロード）が必要
2. リポジトリを clone し、ロジック層のテストが通ることを確認:

```powershell
git clone https://github.com/rami2076/moost.git
cd moost/apps/macos
swift build
swift test
```

`Package.swift` は `#if os(Windows)` で MoostCore / MoostCoreTests のみを対象にする
（MoostApp / MoostAppTests は macOS 専用のため除外）。

### 3.1 CI と同じ条件を手元で再現する場合の注意

- Swift は **6.4.1 以降**を使う（6.0 は新しい MSVC 14.5x のヘッダで
  `ucrt` のモジュール循環が起きる）
- Visual Studio の **C++ ワークロード**と Windows SDK を入れる
- 改行コードは **LF** にしておく（`.gitattributes` で `* text=auto eol=lf`。
  CRLF だと `spec/testdata` の JSONL / JSON のパーステストが落ちる）

## 4. 次の増分（優先順）

### 4.1 UI 方式の決定（ADR を追加）

Windows 用トレイ常駐 UI の方式を ADR（`docs/specs/adr/006-...md`）で決める。
候補とトレードオフ:

| 方式 | ロジック再利用 | トレイ常駐 | 備考 |
|---|---|---|---|
| **Swift + Win32**（swift-win32） | ◎ MoostCore をそのまま使える | ○ Shell_NotifyIcon を P/Invoke | コード共有が最大の利点。UI エコシステムは薄い |
| **WinUI 3 / WPF（C#/.NET）** | △ ロジックを C# で再実装（`packages/core` が参照実装） | ○（WPF はライブラリ、WinUI は Win32 併用） | Windows ネイティブの完成度が高い |
| **Avalonia（C#）** | △ 同上 | ○ | 将来の Linux も視野 |
| **Tauri（Rust + Web）** | △ 再実装 | ○ | 軽量。Rust/TS の追加スタック |

推奨: **MoostCore の再利用を優先するなら Swift + Win32**。
UI の作りやすさを優先するなら WPF（トレイライブラリが成熟）。

### 4.2 最小動線の実装

macOS 版と同じ「一覧 → メモ登録 → 復帰」を通す。

- トレイ常駐（タスクトレイのアイコン + ポップオーバー相当）
- セッション一覧（Claude Code / Codex / pi / Hermes）
- メモ登録（`~/.moost/v2/` 相当の保存先。Windows は `%USERPROFILE%\.moost\v2\`）
- 復帰コマンドのコピー / 端末起動（Windows Terminal `wt.exe`、PowerShell）
- MCP サーバー（`moost mcp` 相当）

### 4.3 エージェント検出の Windows 対応

- Claude Code: `%USERPROFILE%\.claude\`（Windows ネイティブ版 / WSL 版の差異に注意）
- Codex: `%USERPROFILE%\.codex\sessions\`
- pi: ホーム配下の履歴（macOS 実装 `PiSessionHistoryReader.swift` を参照）
- Hermes: `%USERPROFILE%\.hermes\state.db`。**SQLite3 を自前で用意すれば読める**
  （現状の MoostCore は Windows ではスタブ。`#if canImport(SQLite3)` を外す場合は
  sqlite3 の import 方法を Windows 向けに用意する）

### 4.4 リリースサイクル

1. `release.yml` に `build-windows` ジョブを追加（zip 作成 → Release 添付）
2. タグは **`v1.0.0-windows`**（native-migration-plan の「Windows は自系列 v1.0.0」に従う）
3. 配布: GitHub Releases。winget / scoop は余力があれば
4. `RELEASE.md` 7.2 を実態に合わせて更新

## 5. 既知の制約（現状の MoostCore）

- Hermes の `state.db` は読まない（SQLite3 モジュールが無いため一覧は空・抜粋は空文字）
- Kitty のウィンドウ探索は行わない（CoreGraphics が無いため固定パス + グロブのみ）
- プロセス実行に依存する要約テストは macOS 専用（`#if os(macOS)`）
- `/usr/bin/true` を実行する前提の MCP セットアップテストも macOS 専用
  （`AgentPathDetect` は override にも実在チェックをかけるため）
- 要約（Claude haiku / Codex / pi）のサブプロセス実行は Windows で未検証
- テスト数は macOS より少ない（macOS 専用テストを除くため）

## 6. 開発フロー（macOS 側と共通）

- `main` は branch-protected。**必ず PR 経由**（`gh pr merge <n> --squash --delete-branch`）
- CI ゲート: `core` / `desktop` / `mcp_server` / `macos-core` / **`windows-core`** / `osv-scanner`
- リリース: CHANGELOG → バージョン bump → PR → マージ → タグ push（`v<x.y.z>-windows`）
- 仕様の変更は先に `docs/specs/*.md` を更新する（実装は後）

## 7. 参照

- conformance: `spec/conformance.md`（G1 等の検証項目）
- テストデータ: `spec/testdata/`
- スキーマ: `spec/schemas/`
- macOS 実装: `apps/macos/Sources/MoostCore/`（ロジックの参照実装）
- Dart 参照実装: `packages/core/`（C# 等で再実装する場合の仕様の元）
