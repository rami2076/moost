# HANDOFF（2026-11-23）— 「更新マークが出ない」調査の引き継ぎ

この調査は **PC購入のセッションで誤って開始された**もの。moost 開発スレッドでの続きはこのファイルを読んで再開すること。

## 質問（ユーザー）

v2.5.0 をリリースできたか。アプリ画面に**アップデート可能のマークが出ていない**し、**バージョン表記も出ていない**のが気になる。

## 結論（確定分）

**リリースは成功している。サーバ側・判定ロジックは実測で健全。** 未解決は「ユーザーの手元アプリでマークが実際に出ているか」の1点だけで、最有力原因は**アプリが 10:54 JST（リリース時刻）より前から起動しっぱなしで、更新チェックがリリース前の結果で止まっている**こと。

## 検証済み事実（すべてこのセッションで実測）

| 項目 | 結果 |
|---|---|
| GitHub release | `v2.5.0-macos` 公開済み（2026-11-23T01:54:34Z = 10:54 JST）。「Latest」マークつき。アセット `Moost-2.5.0-macos.dmg`（1,174,518 B）。commit `878b6bf`（CHANGELOG 確定 + AppInfo.version bump） |
| リポジトリ | `rami2076/moost` は **PUBLIC**（＝匿名 HEAD がレート制限なく使える） |
| エンドポイント実測 | `curl -sI https://github.com/rami2076/moost/releases/latest` → `HTTP/2 302`、`location: .../releases/tag/v2.5.0-macos`。想定通り |
| 判定ロジック実証 | **インストール済みビルド（v2.4.0）と同コード**の `UpdateChecker.swift`（`git show v2.4.0-macos:apps/macos/Sources/MoostApp/UpdateChecker.swift`）を swiftc で単体ビルドし、`check(currentVersion: "2.4.0-macos")` を実行 → `Optional(UpdateInfo(version: "2.5.0-macos", releaseURL: .../tag/v2.5.0-macos))` を返すことを確認 |
| 手元のアプリ | `/Applications/Moost.app` は **2.4.0**（Info.plist CFBundleShortVersionString、設置日 10/23）。更新未適用なのは想定通り（更新ボタンが 2.5.0 を入れる設計） |
| 表示ゲート（v2.4.0 時点の実物） | 更新ボタン: `ListViews.swift`（一覧画面のツールバー右端、「注意」の右・「終了」の左）の `if model.updateInfo != nil || model.installBroken` のみ。追加ゲート（設定トグル等）なし |
| バージョン表記（v2.4.0 時点の実物） | `SettingsNotesView.swift` の `versionSection()` → `Text("Moost \(AppInfo.displayVersion)")`。**設定タブに常時表示のコード**。2.4.0 でも出るはずのもの |
| チェック発火 | `AppModel.checkForUpdateIfStale()` — 起動時（init 経路）＋ `refresh()`（ポップオーバー表示・タブ切替・フォーム復帰）。間隔 5 分（`updateCheckInterval = 5*60`）。失敗は沈黙（nil） |

## 次にやること（moost スレッドで）

1. **ユーザー操作の確認**: アプリを⏻終了→起動し直す。一覧画面ツールバー右端に更新ボタンが出るか。出れば調査終了
2. それでも出ない場合の切り分け順（推測を混ぜない）:
   - 起動し直した 직후も出ない → `refresh()` の呼び出し経路が実際に叩かれているか（ポップオーバーを開く動作で `checkForUpdateIfStale` が走るか）をログ or ブレークポイントで確認
   - `lastUpdateCheck` の間引き条件が起動時から更新され続けていないか（`AppModel.swift:171-176`）
   - 実行環境のネットワーク差（アプリから見た HEAD のレスポンス。curl と同じとは限らない — プロキシ・DNS・Sparkle 系の干渉）
3. **バージョン表記が本当に空白の場合**（設定タブ最下部に「Moost 2.4.0-macos」の1行すらない）: 表示系の不具合として別途切り分け。まずは画面スクショをユーザーから受け取る
4. 更新ボタンが出たら: クリック → BrewUpdater / brew 経路で 2.5.0 が入るか（brew 管理か dmg 導入かで挙動分岐。`InstallHealthChecker.isBrewManaged`）

## 未検証・注意

- ユーザーが実際どの画面を見て「出ていない」と言ったかは未確認（設定タブと一覧画面のどちらを見ているか）
- 手元アプリが起動しっぱなしの時刻は未確認
- Windows 側のリリース状況（`release-windows` CI は #135/#136 で修正済みだが、Windows リリース自体の状況は見ていない）
- 再現手順の再実行: `git show v2.4.0-macos:...UpdateChecker.swift` + `check("2.4.0-macos")` を swiftc 単体ビルドで実行（このセッションでは scratch で実施済み、恒久ファイルにはしていない）

## 参照

- `UpdateChecker.swift`（releases/latest の 302 Location からタグを読む方式。docs/app-update-check-methods.md 方式7）
- `RELEASE.md`（リリース手順）
- Issue #12（Flutter 版からの更新チェック移植元）
