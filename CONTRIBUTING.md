# Contributing

Moost に興味を持っていただきありがとうございます。バグ報告・機能要望・
プルリクエスト、どれも歓迎します。このドキュメントは、貢献する前に
知っておくと迷わないことをまとめたものです。

## バグを見つけたら / 機能を提案したいとき

[Issues](https://github.com/rami2076/moost/issues) から新規作成してください。
「バグ報告」「機能要望」のテンプレートが用意されているので、それに沿って
書いてもらえると状況を把握しやすいです。

バグ報告では、特に**再現手順**と**環境**（Moost のバージョン、macOS の
バージョン、導入方法）が分かると調査が早く進みます。

## コードを変更したいとき

### 開発環境のセットアップ

```bash
git clone https://github.com/rami2076/moost.git
cd moost

# ロジック層（pure Dart）
cd packages/core
dart pub get
dart test

# デスクトップ UI（Flutter）
cd ../../apps/desktop
flutter pub get
flutter test
```

### 開発の流れ

1. **`main` からブランチを切る**（`main` に直接コミットしない）。
   ブランチ名は `feat/<内容>` / `fix/<内容>` の形式を使う
2. **実装 + テストを書く**。`packages/core`（ロジック層）の変更には
   ユニットテストを必ず添える。`apps/desktop`（UI 層）は必須ではないが、
   状態遷移が絡む変更にはテストがあると助かる
3. **ローカルで検証する**:
   ```bash
   # packages/core
   dart analyze                       # 警告ゼロを維持
   dart test
   dart pub get --enforce-lockfile    # lockfile とバージョンが一致しているか

   # apps/desktop（UI を触った場合）
   flutter analyze
   flutter test
   ```
4. **`CHANGELOG.md` の `## [Unreleased]` セクションに1行追加する**
   （[Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) 形式:
   Added / Changed / Fixed / Removed）
5. **PR を作成する**。テンプレートのチェックリストに沿って検証結果を
   埋めてもらえると助かる。CI（analyze + test + 依存の脆弱性スキャン）が
   通ってからマージする

### 依存パッケージを追加・更新するとき

サプライチェーン対策として、新しい依存を追加する前に以下を確認してください:

- 公開から 7 日以上経過したバージョンを使う（typosquatting・悪意ある
  新規リリースの混入対策）
- メンテナ・公開日・ダウンロード数など、ある程度の実績があるパッケージを選ぶ
- `pubspec.lock` は必ずコミットに含める

### 大きめの変更を考えているとき

アーキテクチャに関わる変更（`AgentAdapter` の抽象を変える、保存形式
`schemaVersion` を上げる、等）や、UI の方針に関わる変更を考えている場合は、
実装に入る前に Issue を立てて相談してもらえると助かります。既存の設計判断と
矛盾しないか、事前にすり合わせできます。

## ライセンス

このプロジェクトへの貢献は [MIT License](./LICENSE) の下で公開されることに
同意したものとみなします。
