# ADR-006: Windows 版を「完全分離実装」にする（C#/.NET 10 + WPF・コード共有なし）

- **ステータス**: Accepted（2026-10-25）
- **決定日**: 2026-10-25
- **関連**: [ADR-005](./005-per-platform-native-over-flutter.md)（プラットフォーム別 native）を Windows について具体化する
- **束ねチケット**: EPIC #110 / 図解資料: [windows-plan.md](../windows-plan.md)

## コンテキスト

ADR-005 で Dart/Flutter を廃止し、プラットフォーム別 native 実装へ移行した。
macOS は Swift/AppKit で v2.0.0〜実装済み（v2.4.0-macos が現行）。

Windows はフェーズ D として未着手だった。着手にあたり、次の要求が示された（2026-10-25）。

1. **機能は macOS 版と同一**にする
2. **OS が違うコードは完全に分離**する（共有コードなし・条件コンパイルなし）
3. **リリース時に確認する事項と分岐を増やさない**（開発体制が 1〜2 人で、リリース速度が落ちると全体が止まる）

この要求の前に、Swift on Windows で MoostCore を共有する案（PR #93）が CI green まで到達していたが、
**1 つのコードベースに OS 分岐が入る**構造になるため #95 でリバートされた。判断材料は
`spike/windows-swift-core` ブランチと PR #93 の CI ログに残っている。

## 決定

1. **コード共有をしない。** 共有するのは `spec/`（schemas / testdata / conformance.md）のみ
2. Windows は **C# / .NET 10（LTS）+ WPF**。トレイ常駐は WinForms の `NotifyIcon` を interop で使う（追加 NuGet なし）
3. `apps/windows/` を**独立ツリー**として新設する。`apps/macos/` は**1 行も変更しない**
4. CI・リリースも**別ワークフロー**にする。既存 `ci.yml` / `release.yml` へのジョブ追加では対応しない
5. 配布は **winget + GitHub Releases の zip** の 2 本。Scoop / Chocolatey / MS Store は対象外
6. バージョンは自系列 **`v1.0.0-windows`** 起点（`v<x.y.z>-<platform>` タグ規約）
7. 合格条件は **`spec/conformance.md` の全項目**を Windows 実装のテストで緑にすること

## 理由

| 観点 | コード共有（Swift on Windows） | 完全分離（本 ADR） |
|---|---|---|
| リリース時の確認事項 | 両方のビルド＋OS 分岐の組合せを毎回確認 | **該当プラットフォームだけ**を確認 |
| 分岐 | `#if os()` がコード・テスト・CI に増える | **0**（各ツリーは単一 OS 前提） |
| CI の可変要素 | Swift 6.4.1 固定・MSVC/ucrt・SDK 設定（#93 で CI 修正 6 回） | .NET SDK がランナーにプリインストール（設定 0 行） |
| 実装コスト | 共有できる（MoostCore 3,714 行） | C# へ翻訳（同規模）。ただし UI は元々共有できない |
| ズレのリスク | 単一実装でズレなし（利点） | `spec/conformance.md` + 共通 Fixture で検知・CI ゲート化 |
| 配布 | OS ごとに独立（brew / winget） | 同じ（独立） |

決め手は **「リリース時に見るものを増やさない」** の一点。実装の重複コストより、
リリースのたびに発生する確認コストと分岐の維持コストを避けることを優先する。

## 却下した代替案

| 案 | 却下理由 |
|---|---|
| Swift + Win32（MoostCore 再利用） | 1 コードベースに OS 分岐が入る。CI の可変要素が多い（#93 の実績） |
| Avalonia（C#） | クロスプラットフォーム志向で、共有への引力が生まれ本方針と逆行する |
| Tauri（Rust + Web） | 別スタックの追加。依存監査（npm / cargo）と WebView2 前提が増える |
| Scoop bucket | 棚が 2 つになりリリース時の確認事項が増える（#109 で不採用決定） |

## 影響

- **追加**: `apps/windows/`（`.sln` / `src/Moost.Core` / `src/Moost.WindowsApp` / `tests/Moost.Core.Tests`）、
  `windows-ci.yml`、`release-windows.yml`、分離ゲート（`scripts/check_platform_separation.sh`）
- **変更**: `release.yml` のトリガを `v*-macos` に限定する（現状 `v*` のため、Windows タグでも
  macOS のビルド・Release 作成が走ってしまう）
- **macOS ツリーの変更**: なし
- **二重保守の受容**: 機能追加は `spec/` を先に更新し、各実装が追随する。conformance をリリースゲートにする
- **費用**: 月額 ¥0（public リポジトリ + 標準ランナー + 署名なし。winget / zip 経由は
  Mark-of-the-Web が付かないため SmartScreen 警告が出ない）

## 未決・保留

- 署名（Azure Trusted Signing 約 $9.99/月）: SmartScreen のクレームが出てから判断する
- 自己更新の実行: v1.0.0 ではコピー提示に留める（`winget upgrade` の起動はしない）
- Scoop: #109 の再検討条件を満たしたら復活させる
- Linux: 引き続き保留

## 参照

- [ADR-005](./005-per-platform-native-over-flutter.md) / [native-migration-plan.md](../native-migration-plan.md) 6〜7 章
- [windows-plan.md](../windows-plan.md)（全体構成図・データフロー・リリースフロー）
- `spec/conformance.md` / `spec/testdata/` / `spec/schemas/`
