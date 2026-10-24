# Moost バージョン管理・改修・リリース手順

- **ステータス**: 運用中（Swift 版 v2.0.0 以降）
- **作成日**: 2026-07-09（2026-10-04 に Swift 版向けへ改訂）
- **前提資料**: [requirements.md](./requirements.md) / [design.md](./design.md)

Swift 版（`apps/macos`）を正とする。Dart/Flutter 版（`apps/desktop` / `packages/core`）は
リファレンス実装として残すが、リリース対象からは外れる（ADR-005）。

## 1. バージョニング

### 1.1 方式: SemVer

`MAJOR.MINOR.PATCH` を使う。

| 上げる桁 | 基準 |
|----------|------|
| MAJOR | メモ・設定ファイルの後方互換が壊れる変更（schemaVersion の引き上げを伴う）、UI/挙動の破壊的変更 |
| MINOR | 機能追加（新画面・新設定・adapter 追加等）。後方互換あり |
| PATCH | バグ修正・文言修正・依存更新のみ |

### 1.1.2 プラットフォーム記号（3 OS 対応を見据えた規約・2026-10-04 導入）

Moost は macOS / Linux / Windows をいずれ native 対応する（#73）ため、
リリース単位をプラットフォームごとに分ける。

| 対象 | 表記 | 例 |
|------|------|-----|
| git タグ | `v<semver>-<platform>` | `v2.0.0-macos` |
| アプリ内バージョン（--version / 設定画面 / MCP serverInfo） | `<semver>-<platform>` | `2.0.0-macos` |
| 配布アセット | `Moost-<semver>-<platform>.<ext>` | `Moost-2.0.0-macos.dmg` |
| brew cask の version | `<semver>-<platform>` | `2.0.0-macos` |
| CHANGELOG の見出し | `[<semver>]`（プラットフォーム共通） | `## [2.0.0]` |

- `platform` は `macos` / `linux` / `windows` の固定 3 値（`AppInfo.platformTag`）
- **`-macos` 等は正式リリース**（GitHub では prerelease にしない）。
  prerelease は `-rc<数>` / `-beta<数>` / `-alpha<数>` のみ
- 各プラットフォームは独立した semver を持つ（進み具合が異なれば個別に上がる。
  互換破壊のような共通の理由では一律に上げる）

### 1.2 バージョンの単一情報源

**`apps/macos/Sources/MoostApp/AppInfo.swift` の `version`（semver）を唯一の情報源とする。**

- 設定画面のバージョン表示・`--version`・MCP serverInfo は `AppInfo.displayVersion`
  （semver + プラットフォーム記号）を使う（手書きの重複を作らない）
- `MoostCore` はプロダクトと同一バージョンで扱い、独立した版番号を振らない
- git タグは `v<x.y.z>-<platform>` 形式（例: `v2.0.0-macos` → 1.1.2）

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

### 3.1 準備（リリースコミット + タグ push）

1. CHANGELOG の `[Unreleased]` を `[x.y.z] - YYYY-MM-DD` に確定
2. `apps/macos/Sources/MoostApp/AppInfo.swift` の version を上げる
3. `swift build && swift test` が通ることを確認してコミット（PR → CI 緑 → マージ）
4. `git tag v<x.y.z>-<platform>` → push

### 3.2 タグ push による自動リリース（macOS）

リリースは GitHub Actions のタグ起動ワークフロー（`.github/workflows/release.yml`）に集約する。

**CI（タグ push で自動実行）:**

1. `swift build -c release`（apps/macos）
2. `.app` バンドル構築（MoostApp + Info.plist + AppIcon.icns）→ ad-hoc 署名 → dmg 化
3. GitHub Release を作成し、dmg と CHANGELOG 該当節を添付
4. Homebrew tap の cask を新バージョンへ bump（cask version = `x.y.z-platform`）

**リリース後の確認:**

- dmg をクリーンな環境（または別ユーザー）でインストールし、
  起動 → 一覧表示 → メモ登録 → 復帰の最小動線を確認する
- 設定画面のバージョン表示が `x.y.z-platform` になっていることを確認する

### 3.3 hotfix

リリース済みバージョンの緊急修正は、タグから `hotfix/<x.y.z+1>` を切って
修正 → PATCH を上げて 3.1/3.2 と同じ手順でリリースし、`main` にもマージして戻す。

### 3.4 Homebrew tap への自動反映と deploy key

リリース（`-rc` を含まないタグ）時、release.yml が
[rami2076/homebrew-tap](https://github.com/rami2076/homebrew-tap) の
`Casks/moost.rb` を丸ごと再生成して push する（version / sha256 / dmg URL）。
ユーザーは `brew install --cask rami2076/tap/moost` で導入、`brew upgrade` で更新できる。
cask の version はタグ規約どおり `x.y.z-platform`（例: `2.0.0-macos`）。

**認証の構成**（Actions の `GITHUB_TOKEN` は自リポジトリにしか効かないため）:

- 公開鍵: homebrew-tap の Settings → Deploy keys（`read_only=false` = push 許可）
- 秘密鍵: moost の Actions secret `TAP_DEPLOY_KEY`（暗号化保管・閲覧不可）
- 鍵はこの用途専用の使い捨て品。**バックアップは持たない**
  （失効・漏洩時は下記ローテーションで作り直すだけ。手元や Drive に控えを置かない）

**鍵のローテーション手順**（漏洩疑い・紛失時。所要 3 分）:

```bash
# 1. 旧 deploy key を削除（id は一覧で確認）
gh api repos/rami2076/homebrew-tap/keys --jq '.[] | {id, title}'
gh api -X DELETE repos/rami2076/homebrew-tap/keys/<id>

# 2. 新しい鍵ペアを作成し、公開鍵を tap へ・秘密鍵を secret へ登録して手元を削除
ssh-keygen -t ed25519 -N '' -C "moost-release-tap-bump" -f /tmp/tap_key -q
gh api -X POST repos/rami2076/homebrew-tap/keys \
  -f title="moost release.yml (tap bump)" \
  -f key="$(cat /tmp/tap_key.pub)" -F read_only=false
gh secret set TAP_DEPLOY_KEY --repo rami2076/moost < /tmp/tap_key
rm -f /tmp/tap_key /tmp/tap_key.pub
```

**登録状態の確認**:

```bash
gh secret list --repo rami2076/moost          # TAP_DEPLOY_KEY があること
gh api repos/rami2076/homebrew-tap/keys       # read_only: false の鍵があること
```

## 4. 署名・公証（macOS）についての現状整理

- 当面は **ad-hoc 署名**（Swift 版 1.0.4 と同じ）。初回起動時に Gatekeeper の警告が出るため、
  README に回避手順（右クリック → 開く）を書く
- OSS として広く配るなら Developer ID 署名 + notarization（Apple Developer Program、有料）が必要。
  これは public 化のタイミングで判断する（フェーズ 3 課題）

## 5. チェックリスト（リリース時）

- [ ] CHANGELOG が確定している（Unreleased が空になった）
- [ ] `AppInfo.version` がタグの semver と一致している
- [ ] `swift build && swift test`（apps/macos）が通っている
- [ ] schemaVersion を変えた場合: マイグレーション実装 + テストがあり、MAJOR を上げている
- [ ] クリーン環境で最小動線（一覧 → メモ登録 → 復帰）を確認した
- [ ] 設定画面のバージョン表示が `x.y.z-platform` になっている

## 6. リリースフローのトラブルシューティング（練習リリースで発見）

2026-09-03 の練習リリース（v1.11.0-rc1 / rc2）で発生した失敗と対処を記録する。
同様の問題は RELEASE_NOTES の生成・CI で再発し得るため、手順を変更する際は
この節も更新すること。

### 失敗 1: CI の `flutter pub get --enforce-lockfile` が失敗（exit 65）

- 症状: desktop（analyze + widget test）が "Failed to update packages" で失敗
- 原因: ローカルの Flutter 3.47.2 で `flutter pub get` を実行し、`apps/desktop/pubspec.lock`
  の transitive 依存（intl / matcher / meta など約 26 箇所）が更新されたままコミットされた。
  CI は Flutter 3.44.5 固定のため、SDK が要求する版（より古い）と lockfile が一致しなかった
- 対処: `git checkout main -- apps/desktop/pubspec.lock` で main の lockfile へ戻して再 push
- 教訓: 依存の追加・削除以外で lockfile が変わるのはローカル pub get のせい。
  **CI の Flutter バージョン（3.44.5）を基準に lockfile を固定**し、無関係な差分はコミットしない

### 失敗 2: rc1 の build-linux が `fl_dart_project_set_enable_impeller` で失敗

- 症状: `error: use of undeclared identifier 'fl_dart_project_set_enable_impeller'` → Build process failed
- 原因: ローカル（Flutter 3.47.2）の `flutter_linux.h` には存在するが、
  **CI の Flutter 3.44.5 には無い API** を呼んでいた（ローカルビルドは通る）
- 対処: この API 呼び出しを削除し、ソフトウェアレンダリングは
  `FLUTTER_ENGINE_SWITCHES=--enable-software-rendering`（環境変数・両バージョンで有効）に一本化
- 教訓: **CI で固定している Flutter バージョンでビルドを通す**こと。新 API を使う際は
  CI のヘッダ（bin/cache/artifacts/engine/linux-*/flutter_linux/）で存在確認する

### 失敗 3: rc2 の「Extract changelog section」が失敗（awk: unterminated regexp）

- 原因 A: スラッシュ形式の正規表現リテラル `/^## \\[/` が、シェルクォートを経由した
  `\\` により `\\[` と解釈され「文字クラスが閉じていない」エラーになった
- 原因 B: `VERSION=1.11.0-rc2` のまま `## [1.11.0-rc2]` を検索しており、CHANGELOG の
  見出し `## [1.11.0]` に一致しなかった（論理バグ）
- 対処: タグから `-` 以降を除いた `V` で検索し、awk の照合を **`index($0, "## [<ver>]") == 1`** に変更
  （正規表現を使わないためバックスラッシュ・mawk/gawk 差異に依存しない）
- 教訓: **prerelease タグを打つ際は CHANGELOG 節の検索から `-` 以降を除く**。
  awk のバックスラッシュはクォート×実装（mawk は文字列 RE 中の `\\` を
  2 文字として扱い invalid regexp になる）の合わせ技で壊れやすいため、
  **照合は `index()` で行う方が確実**
