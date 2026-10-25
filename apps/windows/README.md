# apps/windows — Windows native 実装（C#/.NET 10 + WPF）

macOS 版（`apps/macos/`・Swift/AppKit）と**同一機能**を、**コード共有なし**で実装する。
決定は [ADR-006](../../docs/specs/adr/006-windows-fully-separated-wpf.md)、
全体構成図は [windows-plan.md](../../docs/specs/windows-plan.md)。

## 構成

```
apps/windows/
├── Moost.slnx                    # ソリューション（.NET 10 の新形式・XML）
├── global.json                   # .NET SDK の pin（10.0 / rollForward: latestFeature）
├── Directory.Build.props         # 共通設定（Nullable・警告=エラー・lock ファイル）
├── Directory.Packages.props      # NuGet 中央パッケージ管理（バージョンはここだけに書く）
├── .editorconfig                 # LF 固定・UTF-8
├── src/
│   ├── Moost.Core/               # ロジック層（net10.0・UI 非依存）
│   └── Moost.WindowsApp/         # WPF UI（net10.0-windows・NotifyIcon interop）→ Moost.exe
└── tests/
    └── Moost.Core.Tests/         # xUnit
```

依存方向は **UI → Core → OS** の一方通行。`Moost.Core` は WPF / WinForms を参照しない
（macOS の「MoostCore は AppKit/SwiftUI を import しない」性質の写像）。

## 必要なもの

- .NET SDK **10.0**（LTS）。`global.json` で 10.0 系に固定している
  - 管理者権限なしで入れる場合:
    `powershell -NoProfile -ExecutionPolicy Bypass -Command "& $env:TEMP\dotnet-install.ps1 -Channel 10.0 -InstallDir $env:LOCALAPPDATA\Microsoft\dotnet"`

## ビルドとテスト

```powershell
cd apps/windows
dotnet restore
dotnet build -c Release
dotnet test -c Release
```

成果物は `src/Moost.WindowsApp/bin/Release/net10.0-windows/Moost.exe`。

### ソリューションは `.slnx`（.NET 10 の新形式）

`.slnx` は XML で人間が読める目次ファイルで、旧 `.sln`（GUID の羅列）より差分が小さい。
**配布物・インストール先・実行環境には影響しない**（開発時の束ね役にすぎない）。

```xml
<Solution>
  <Folder Name="/src/">
    <Project Path="src/Moost.Core/Moost.Core.csproj" />
    <Project Path="src/Moost.WindowsApp/Moost.WindowsApp.csproj" />
  </Folder>
  <Folder Name="/tests/">
    <Project Path="tests/Moost.Core.Tests/Moost.Core.Tests.csproj" />
  </Folder>
</Solution>
```

注意:

- `.sln` と `.slnx` を同時に置くと `dotnet build` が対象を決められずエラーになる。**`.slnx` のみを置く**
- プロジェクトの追加は `dotnet sln Moost.slnx add <path>`（手書きしない）
- 旧形式が必要になったら `dotnet sln migrate` の逆相当として `.sln` を再生成できる

## テストデータは spec/ を直接読む

Fixture はコピーせず、リポジトリ直下の `spec/`（製品契約の正本）をそのまま使う
（`tests/Moost.Core.Tests/SpecPaths.cs`）。これにより macOS / Windows / Dart の各実装が
**同一の Fixture** で検証される。

## リリース用ビルド（検証済み）

```powershell
dotnet publish src/Moost.WindowsApp/Moost.WindowsApp.csproj `
  -c Release -r win-x64 --self-contained `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:Version=<x.y.z> -o dist
```

- **`IncludeNativeLibrariesForSelfExtract=true` が必須**。これが無いと WPF のネイティブ DLL
  （`wpfgfx_cor3.dll` / `PresentationNative_cor3.dll` / `D3DCompiler_47_cor3.dll` /
  `PenImc_cor3.dll` / `vcruntime140_cor3.dll`）が exe の隣に残り、単一 exe にならない
- 実測（2026-10-25・SDK 10.0.402）: `Moost.exe` **165MB** → zip **67MB**
- 配布 zip には `*.pdb` を含めない
- フレームワーク依存（`--self-contained` なし）にすると数 MB になるが、
  **.NET デスクトップランタイムの導入が前提**になるため採用しない

## 現在の状態（#101 完了・Core 完成）

| conformance | 項目 | 状態 |
|---|---|---|
| A | JSON 永続基盤（アトミック書き込み・破損退避・エラー伝播） | ✅ |
| B | memos.json（エンベロープ・寛容読み・可変/不変・parseTags・日付） | ✅ |
| C | settings.json（項目別フォールバック・ENUM 化しない・自動起動を保存しない） | ✅ |
| D | projects.json（エンベロープ・displayName の導出） | ✅ |
| E | 直近セッション一覧（history 集約・フォーク除外・limit） | ✅ |
| F | 表題フォールバック（runes 50）/ ai-title 末尾 64KB | ✅ |
| G | 復帰コマンドとシェル escape | ✅ |
| H | プラットフォーム受け入れ（既知のハマりどころの踏襲） | ☐ #103 |

- [x] ソリューション（`.slnx`）・3 プロジェクト・CI ゲート（`windows-ci.yml`）
- [x] spec への配線（conformance の項目数と Fixture の到達性をテスト）
- [x] **Moost.Core の永続層とモデル（A〜D）**
- [x] **復帰コマンドと PowerShell escape（G）**
- [x] **一覧・表題（E・F）**：claude / codex の history 集約、rollout からの cwd、ai-title の末尾走査
- [x] **4 エージェントの一覧**：pi（JSONL）と Hermes（SQLite 読み取り専用）を追加し、統合を 4 系統に拡張
- [x] **CLI パス検出**：設定上書き → 既知パス → `where.exe` の 3 段構え
- [x] **会話抜粋と要約（#101 後半）**
  - 抜粋: claude / codex / pi / hermes のセッションから直近 N ラリーをテキスト化
  - 要約: `claude -p`（haiku 固定）と `codex exec --ephemeral`。pi / hermes はローカル抽出をそのまま返す（API 消費ゼロ）
  - 要約結果は**永続化しない**メモリキャッシュのみ（ADR-002）
- [x] 単一 exe での publish 経路を実機で検証（上記）
- [x] **トレイ常駐とポップオーバー（#102）**：NotifyIcon + 枠なしウィンドウ（タスクバー非表示・Topmost・フォーカス喪失で隠す）
- [x] **復帰起動・自動起動の土台（#103 前半）**
  - `TerminalLauncher`（`wt.exe` → `powershell.exe` フォールバック・`-NoExit`）
  - `AutoStartService`（`HKCU\...\Run` の実状態を正とする・引用符で囲んで登録）
  - `MainViewModel`（UI 非依存。一覧・メモ・プロジェクト・設定・復帰・要約の操作）
- [x] **画面一式（#103 後半）**：セッション一覧 / メモ（登録・編集・削除）/ プロジェクト / 詳細（要約）/ 設定 / 注意 の 6 画面を ViewModel に接続

テストは `dotnet test` で **224 件**。

### サブプロセス実行の注意（Windows）

- stdout / stderr は**同時に**非同期で読み切る（片方だけ読むとパイプが詰まってハングする）
- タイムアウトで**プロセスツリーごと** kill する（CLI が固まっても UI を止めない）
- `StandardOutputEncoding = UTF-8` にしているのは、claude / codex が **Node 製で UTF-8 を書く**ため。
  Windows PowerShell 5.1 は OEM コードページで書くので、`.ps1` を直接叩く経路では日本語が化ける（本番の経路では起きない）
- `.cmd` / `.bat`（npm シミング）は `cmd.exe /c` を挟んで起動する

## 依存（NuGet）

| パッケージ | 用途 | 備考 |
|---|---|---|
| `Microsoft.Data.Sqlite` 10.0.13 | Hermes の `state.db` を**読み取り専用**で読む | `SQLitePCLRaw` 経由で `e_sqlite3` を同梱するため、追加のネイティブ配布は不要 |

依存は `Directory.Packages.props` の 1 か所で管理し、`packages.lock.json` をコミットする（CI は `--locked-mode`）。

### Windows 固有の解釈

- **ポップオーバーの位置は macOS と上下が逆**。macOS はメニューバーが上端なので「アイコンの直下」だが、
  Windows はタスクトレイが**下端（右下）**なので「作業領域の右下に寄せてトレイの上側」に出す
  （`Moost.Core.Layout.PopoverLayout`。純粋関数なのでテストできる）
- トレイアイコンは **埋め込みリソース**（`Assets\moost.ico`・16/24/32/48 の 4 サイズ）。
  Content にすると単一 exe 配布で欠けるため
- 座標変換: WinForms の作業領域・カーソルは**物理ピクセル**、WPF の `Left/Top` は **DIP**。
  `VisualTreeHelper.GetDpi` のスケールで割ってから計算する（マルチ DPI 環境の完全対応は #103 で詰める）
- 起動時はウィンドウを出さずトレイのみ（`ShutdownMode.OnExplicitShutdown`・トレイメニューの「終了」で終わる）

- `Project.DisplayName` は区切りを `/` と `\` の両方で扱う（リファレンス実装は POSIX 前提で `/` のみ）。
  データ契約の期待値は「最後のディレクトリ名」であり、区切りの種類に依存しない
- 保存先は `%USERPROFILE%\.moost\v2\`。Windows には旧世代（v1）のデータが無いため、v1 → v2 の移行は行わない
- 復帰コマンドは `Set-Location -LiteralPath '<path>'; <agent> ...`（`&&` は PowerShell 5.1 に無い・
  `cd` は `[` `]` `*` をワイルドカードとして解釈するため `-LiteralPath`）
- Claude Code の内部環境変数除去は `env -u` の代わりに
  `Get-ChildItem Env:CLAUDE_*, ... | Remove-Item` を使う
- CLI の既知パスは **`%USERPROFILE%\.local\bin\<cmd>.exe`**（ネイティブインストーラ）と
  **`%APPDATA%\npm\<cmd>.cmd`**（npm グローバル）。`.cmd` は実行に `cmd.exe` を挟む必要がある
  （`AgentPathDetect.RequiresCommandShell`）
- Hermes の `state.db` は `Mode=ReadOnly` + `PRAGMA query_only=ON` で開き、接続プールは使わない
  （ハンドルを残すと Hermes 側の書き込みを邪魔する可能性があるため）

プレースホルダの `MainWindow` は #102 / #103 で置き換える。
