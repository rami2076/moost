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

## 現在の状態（#98 時点）

| conformance | 項目 | 状態 |
|---|---|---|
| A | JSON 永続基盤（アトミック書き込み・破損退避・エラー伝播） | ✅ |
| B | memos.json（エンベロープ・寛容読み・可変/不変・parseTags・日付） | ✅ |
| C | settings.json（項目別フォールバック・ENUM 化しない・自動起動を保存しない） | ✅ |
| D | projects.json（エンベロープ・displayName の導出） | ✅ |
| E | 直近セッション一覧・表題 | ☐ #99 |
| F | 表題フォールバック / ai-title | ☐ #99 |
| G | 復帰コマンドとシェル escape | ☐ #100 |

- [x] ソリューション（`.slnx`）・3 プロジェクト・CI ゲート（`windows-ci.yml`）
- [x] spec への配線（conformance の項目数と Fixture の到達性をテスト）
- [x] **Moost.Core の永続層とモデル（A〜D）**
- [x] 単一 exe での publish 経路を実機で検証（上記）
- [ ] 一覧・表題（#99）、escape（#100）、readers・要約（#101）
- [ ] トレイ常駐・画面（#102 / #103）

テストは `dotnet test` で **55 件**（骨組み 5 + 永続層 50）。

### Windows 固有の解釈

- `Project.DisplayName` は区切りを `/` と `\` の両方で扱う（リファレンス実装は POSIX 前提で `/` のみ）。
  データ契約の期待値は「最後のディレクトリ名」であり、区切りの種類に依存しない
- 保存先は `%USERPROFILE%\.moost\v2\`。Windows には旧世代（v1）のデータが無いため、v1 → v2 の移行は行わない

プレースホルダの `MainWindow` は #102 / #103 で置き換える。
