# Moost バージョン管理・改修・リリース手順

- **ステータス**: ドラフト
- **作成日**: 2026-07-09
- **前提資料**: [requirements.md](./requirements.md) / [design.md](./design.md)

Swift 版の `RELEASE.md` + `scripts/build-dmg.sh`（VERSION もそこで管理）に相当する運用を
Dart/Flutter 版向けに定義する。実装リポジトリ作成時に本書を `RELEASE.md` として持ち込む。

## 1. バージョニング

### 1.1 方式: SemVer

`MAJOR.MINOR.PATCH` を使う。

| 上げる桁 | 基準 |
|----------|------|
| MAJOR | メモ・設定ファイルの後方互換が壊れる変更（schemaVersion の引き上げを伴う）、UI/挙動の破壊的変更 |
| MINOR | 機能追加（新画面・新設定・adapter 追加等）。後方互換あり |
| PATCH | バグ修正・文言修正・依存更新のみ |

### 1.2 バージョンの単一情報源

**`apps/desktop/pubspec.yaml` の `version`（`x.y.z+ビルド番号`）を唯一の情報源とする。**

- 設定画面のバージョン表示は package_info_plus 等で pubspec から取得する（手書きの重複を作らない）
- `packages/core` は当面プロダクトと同一バージョンで扱い、独立した版番号を振らない。
  pub.dev への単独公開を始める時点で分離する
- git タグは `v<x.y.z>` 形式（例: `v1.2.0`）

### 1.3 アプリのバージョンとデータの schemaVersion は別物

- アプリのバージョン: リリースのたびに上がる
- `memos.json` / `settings.json` の `schemaVersion`: **形式が変わったときだけ**上がる
- schemaVersion を上げる変更は必ず MAJOR リリースとし、読み込み時マイグレーション
  （旧形式を読んで新形式で書き出す。元ファイルはバックアップを残す）を同梱する。
  保存ディレクトリの `v1` → `v2` 切替は「マイグレーション不能な根本的変更」のときだけ使う

## 2. 改修手順（日常の開発フロー）

1. **ブランチを切る**: `main` から `feat/<内容>` / `fix/<内容>` を作る。`main` に直接コミットしない
2. **実装 + テスト**: ロジック変更には必ずユニットテストを付ける（core はテスト必須、UI 層は対象外）
3. **ローカル検証**:
   ```bash
   dart analyze                       # 静的解析（警告ゼロ）
   dart test                          # packages/core（全パス）
   dart pub get --enforce-lockfile    # lockfile と一致するか確認
   ```
4. **CHANGELOG.md を更新**: `## [Unreleased]` セクションに 1 行追加
   （Keep a Changelog 形式: Added / Changed / Fixed / Removed）
5. **PR を作り CI が通ってからマージ**: CI は analyze + test + osv-scanner を実行する。
   個人開発でもこの経路を崩さない（履歴と CI 通過の保証が残る）

依存の追加・更新は [design.md 8 章](./design.md#8-依存管理とサプライチェーン対策) の
サプライチェーンルール（クールダウン 7 日・審査・lockfile）に従う。

## 3. リリース手順

### 3.1 フェーズ 1（core のみ・アプリ配布なし）

git タグを打つだけの軽量リリースとする。

1. CHANGELOG の `[Unreleased]` を `[x.y.z] - YYYY-MM-DD` に確定
2. pubspec.yaml の version を上げる
3. `dart analyze && dart test` が通ることを確認してコミット
4. `git tag v<x.y.z>` → push

### 3.2 フェーズ 2 以降（macOS アプリ配布）

リリースは GitHub Actions のタグ起動ワークフローに集約する（Swift 版 `build-dmg.sh` の置き換え）。

**手元でやること:**

1. CHANGELOG の `[Unreleased]` を `[x.y.z] - YYYY-MM-DD` に確定
2. pubspec.yaml の version を `x.y.z+<ビルド番号>` に上げる
3. リリースコミットを作成し PR → マージ
4. `git tag v<x.y.z>` → push

**CI（タグ push で自動実行）:**

1. `dart analyze` / `dart test` / osv-scanner
2. `dart pub get --enforce-lockfile` で依存を固定取得
3. `flutter build macos --release`
4. .app の署名（当面は ad-hoc 署名。Swift 版と同じ）→ dmg 化
5. GitHub Release を作成し、dmg と CHANGELOG 該当節を添付

**リリース後の確認:**

- dmg をクリーンな環境（または別ユーザー）でインストールし、
  起動 → 一覧表示 → メモ登録 → 復帰の最小動線を確認する
- 設定画面のバージョン表示が上がっていることを確認する

### 3.3 hotfix

リリース済みバージョンの緊急修正は、タグから `hotfix/<x.y.z+1>` を切って
修正 → PATCH を上げて 3.1/3.2 と同じ手順でリリースし、`main` にもマージして戻す。

## 4. 署名・公証（macOS）についての現状整理

- 当面は **ad-hoc 署名**（Swift 版 1.0.4 と同じ）。初回起動時に Gatekeeper の警告が出るため、
  README に回避手順（右クリック → 開く）を書く
- OSS として広く配るなら Developer ID 署名 + notarization（Apple Developer Program、有料）が必要。
  これは public 化のタイミングで判断する（フェーズ 3 課題）

## 5. チェックリスト（リリース時）

- [ ] CHANGELOG が確定している（Unreleased が空になった）
- [ ] pubspec.yaml の version がタグと一致している
- [ ] `dart analyze` / `dart test` / `--enforce-lockfile` が通っている
- [ ] schemaVersion を変えた場合: マイグレーション実装 + テストがあり、MAJOR を上げている
- [ ] クリーン環境で最小動線（一覧 → メモ登録 → 復帰）を確認した
- [ ] 設定画面のバージョン表示が新しい版になっている
