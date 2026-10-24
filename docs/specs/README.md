# Moost 仕様書（正の情報源）

Moost の要求・要件・設計・移行計画の**正**はこのディレクトリです
（2026-10-23 に docs リポジトリ `project/moost/` から移設）。

## 読み順

| ファイル | 内容 |
|---|---|
| [overview.md](./overview.md) | 全体像・用語・リポジトリ構成（最初に読む） |
| [CONTEXT.md](./CONTEXT.md) | 用語集（「セッション」「メモ」「登録プロジェクト」等の定義） |
| [requirements.md](./requirements.md) | 要求・要件（機能一覧・データ契約） |
| [design.md](./design.md) | 画面設計・アーキテクチャ判断・既知のハマりどころ |
| [native-migration-plan.md](./native-migration-plan.md) | Flutter → native 移行計画・フェーズ別ロードマップ・**Windows 版（フェーズ D）の計画** |
| [adr/](./adr/) | Architecture Decision Records（ADR-001〜005） |
| [RELEASE.md](../../RELEASE.md) | バージョニング・リリース手順（CI・タグ規約・cask） |

## プラットフォーム別の実装状況

- **macOS native**: 実装済み（`apps/macos/`、v2.0.0〜）
- **Windows**: フェーズ D。MoostCore の Windows ビルド・テストは CI ゲート済み
  （`windows-core`）。UI とリリースワークフローは未着手
  → 引き継ぎは [windows-handoff.md](./windows-handoff.md)
- **Linux**: 保留（フェーズ D の後）

## 更新ルール

- 仕様の変更はこのディレクトリの Markdown を先に更新する（実装はその後）
- 旧 docs リポジトリ側の HTML は閲覧用の残置物であり、正ではない
