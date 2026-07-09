# Moost

Memo + Roost — AI コーディングエージェント CLI（まず Claude Code）のセッションにメモを付けて記録し、ワンクリックでセッションへ復帰できるシステムトレイ常駐アプリ。

## 構成

```
packages/core/   ロジック層（pure Dart・UI 非依存）
apps/desktop/    Flutter デスクトップ UI（フェーズ 2）
```

## 開発

```bash
cd packages/core
dart pub get
dart test
dart run bin/moost.dart --help   # CLI サンプル
```

## ドキュメント

要求・要件・設計資料は docs リポジトリの `project/moost/` を正とする。
リリース手順は [RELEASE.md](./RELEASE.md)。
