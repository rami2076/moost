# apps/windows — Windows native 実装（C#/.NET 10 + WPF）

macOS 版（`apps/macos/`・Swift/AppKit）と**同一機能**を、**コード共有なし**で実装する。
決定は [ADR-006](../../docs/specs/adr/006-windows-fully-separated-wpf.md)、
全体構成図は [windows-plan.md](../../docs/specs/windows-plan.md)。

## 構成

```
apps/windows/
├── Moost.sln                     # ソリューション
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

## テストデータは spec/ を直接読む

Fixture はコピーせず、リポジトリ直下の `spec/`（製品契約の正本）をそのまま使う
（`tests/Moost.Core.Tests/SpecPaths.cs`）。これにより macOS / Windows / Dart の各実装が
**同一の Fixture** で検証される。

## 現在の状態（#97 時点）

- [x] ソリューション・3 プロジェクト・CI ゲート（`windows-ci.yml`）
- [x] spec への配線（conformance の項目数と Fixture の到達性をテスト）
- [ ] Moost.Core の実装（#98 以降）
- [ ] トレイ常駐・画面（#102 / #103）

プレースホルダの `MainWindow` は #102 / #103 で置き換える。
