# Moost Native 移行: リポジトリ構成とリリース方式の検討

- **ステータス**: 検討ドラフト（未決は Dart 保存場所のみ。9 章）
- **作成日**: 2026-09-27
- **前提資料**: [design.md](./design.md) / [RELEASE.md](../../RELEASE.md) / [ADR-001](./adr/001-dart-flutter-over-swift.md)
- **対応 ADR**: [ADR-005](./adr/005-per-platform-native-over-flutter.md)（ADR-001 を supersedes する案）

## 1. 背景と問いの整理

ADR-001 で「クロスプラットフォーム対応」を掲げて Swift 先行実装を Dart/Flutter に書き直したが、
方針を転換し **プラットフォーム単位の Native 実装**へ移行する（Dart は廃止）。

ここでいう「Native」とは、各 OS の公式言語・公式 UI スタックでそのまま実装すること
（macOS = Swift/AppKit、Windows = C#/.NET、Linux = 保留）。WebView 経由の擬似 Native
（Tauri/Electron）は方針に合わないので対象外とする。

移行しても失わないもの:

| 資産 | 扱い |
|------|------|
| データ契約（`memos.json`/`settings.json`・`schemaVersion`） | **形式は無変更で固定**。プラットフォーム共通の製品契約であり、ここを壊さないことが移行の成功条件。保存先は native 世代で `~/.moost/v2/` に新設（v1 からの移行処置は 6 章） |
| 既知のハマりどころ（design.md 7 章） | そのまま引き継ぐ（GUI の PATH、パイプ詰まり、フォーク除外、シェル escape、ポップオーバー、App Sandbox の検証済み知見） |
| Swift 先行実装（claude-session-memo） | macOS 実装の出発点とする |
| リリース運用（RELEASE.md の SemVer・タグ・CHANGELOG の規約） | 手順はそのまま流用可。タグ push の自動化として継続 |
| AgentAdapter 抽象 | プラットフォームによらない統一。各実装内の抽象として維持 |

## 2. 判断の焦点: 共通ロジック層をどうするか

UI はプラットフォーム固有で共有できない。構造的な判断の焦点は
**共通ロジック層（core）を共有するか否か**の一点である。

| 案 | 概要 | 評価 |
|----|------|------|
| A. Rust 共通 core + FFI | ロジックを Rust で実装し、UniFFI 等で各言語のバインドを生成 | 実装を一つに保てる利点があるが、FFI の環境整備のコストが大きく、個人開発には重すぎる |
| B. プラットフォームごとに実装 + 仕様の共有 | core は各実装。代わりに**データ仕様（スキーマ）とテストデータ**をリポジトリ上位の `spec/` に置き、同一の検査で実装のズレを監視する | **推奨**。core は小規模（JSONL の読み取り・CRUD・文字列処理が中心）で実装コストは低い |
| C. C++ 共通 core | A と同質で、さらに環境依存が強い | 現時点では対象外 |

推奨は B。根拠:

1. core のコード量は小さい（design.md 1 章の 7 コンポーネント）。実装の大半は UI であり、
   それはそもそも共有できない。共通化のコストより個別実装の単純さを選ぶ
2. FFI は型の変換・データ構造の理解も必要で、1〜2 人の維持には負担が大きい
   （クロスコンパイルのツールを整え、各 OS の開発環境を構築する手間が続く）
3. 重複実装による差異（バラつき）は規則で防ぐ:
   - `spec/schemas/` — memos.json / settings.json の JSON スキーマ（検索可能な検証基準）
   - `spec/testdata/` — 共通の検査用 Fixture（history.jsonl、壊れた行を含むセッション
     JSONL、ai-title、フォーク除外マーカー、バッククォート等の危険な文字を含む。
     整頓したテストデータを収集する）
   - `spec/conformance.md` — 各実装が必ず満たす検証項目のチェックリスト
4. Dart 実装は当面**リファレンス実装**としてリポジトリに残す（削除しない）。
   各実装が同じテストデータで突き合わせる

実装間でズレやすい箇所は spec 側に明確に書く:

- history.jsonl の集約規則（sessionId 単位・最新 timestamp 採用・除外マーカー）
- ai-title の末尾 64KB 読取り + 逆順走査と、先頭 50 文字のフォールバック
- アトミック書き込みと、破損時の退避（リネーム保全）
- 復帰コマンドのシェルエスケープ規則

## 3. 各プラットフォームの技術選定

| プラットフォーム | 推奨 | 選定理由 | 次点（候補） |
|----------------|-------|-----------|-------------|
| macOS | Swift + AppKit（SPM） | 先行実装が NSStatusItem + NSPopover のトレイ常駐を一通り検証済み。ポップオーバーの仕様（design.md 6 章）は AppKit が本道 | SwiftUI 単体ではトレイ対応が手薄。プラグイン依存となり危険 |
| Windows | C#/.NET + WPF | トレイ（NotifyIcon）と常駐のサポートが最も厚い。自己完結な単一ファイル publish が可能 | WinUI 3 はトレイ周辺が薄い。C++/Win32 は手強すぎて険しい |
| Linux | 保留 | 先行実装がなく、見通し | GTK/C、Qt 等。将来に備える |
| MCP サーバー | **アプリ内蔵の CLI サブコマンド `moost mcp` が主**（アプリ単体で完結） | ユーザに Node の有無を前提させない（「Node が入っている前提は賢くない」という判断、2026-09-27）。アプリ同梱バイナリの絶対パスを MCP クライアントに登録する。表面積は 4 ツール・読取専用で小さいので、プラットフォーム別の重複実装も許容範囲 | Node を持つ環境が支配的な MCP サーバー（`npx -y`）は Dart 実装の `mcp_server` がリファレンスとして残る。将来ユーザの Node 普及率が上がるなら再評価 |

## 4. リポジトリ構成の案（monorepo 継続を推奨）

`rami2076/moost` をそのまま使う。プラットフォームごとにリポジトリを分ける案（multirepo）は、
現在の開発規模（1〜2 人）では不相応。単一製品・単一 CHANGELOG・単一バージョン・
単一のデータ契約を貫くので、monorepo が妥当である。

```
moost/
├─ spec/                        # ★ 製品契約の正本
│   ├─ schemas/                 #   memos.schema.json / settings.schema.json
│   ├─ testdata/               #   共通の検査用 Fixture
│   └─ conformance.md           #   各実装の検証項目チェックリスト
├─ apps/
│   ├─ macos/                   # Swift Package（Sources/MoostCore, Sources/MoostApp, Tests/）
│   ├─ windows/                 # 後日（C#/.NET、csproj + Directory.Packages.props）
│   └─ linux/                   # 保留
├─ packages/
│   └─ mcp-server/              # TS/Node（npm 公開。後日）
├─ docs/adr/                    # ADR は実装リポジトリに同居させる
├─ CHANGELOG.md                 # Keep a Changelog（単一ファイル・プラットフォーム別ヘッダ）
└─ .github/workflows/           # ci.yml（paths フィルタでプラットフォーム別）/ release.yml
```

multirepo が向く場合（将来の参考）: CI のビルド時間が許容できなくなるとき、または
プラットフォームごとに開発者の権限を分離する必要が生じるとき。その場合は `spec/` を
基準となるリポジトリとして分離し、各リポジトリの履歴を明確にする。

## 5. バージョン管理とリリース手法

### 5.1 バージョンの単一情報源は「プラットフォーム別接タグ」

タグは `macos/v<x.y.z>` / `windows/v<x.y.z>`（プラットフォーム別接 + SemVer）。
**バージョンはプラットフォームごとに独立した系列とする**（2026-09-27 決定）。
全プラットフォームを一気に開発することは難しいため、共有版番号では未発売の
プラットフォームの版番号だけを吊り上げる結果になる。リポジトリ内のバージョン表記
（xcconfig の MARKETING_VERSION、csproj の `<Version>`）はコミットしない。ビルド時に
CI がタグから読み取り注入する（接頭部分であるプラットフォーム名は除去し、素数の
 SemVer 文字列にして製品に渡す）。

```bash
# macOS
xcodebuild archive ... MARKETING_VERSION="$GIT_TAG" CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
# Windows
dotnet publish -p:Version="$GIT_TAG"
```

- SemVer はプラットフォームごとに独立して適用する。**MAJOR はプラットフォーム内の
  意味**：そのプラの UX・配布の破壊、およびデータ契約移行の採用
- `schemaVersion` は版番号から分離・登記する（データ契約の単一情報源）。データ契約の
  変更は製品イベントなので CHANGELOG と spec/ に記録し、採用する各プラットフォームは
  自系列の MAJOR を上げる
- ビルド番号は CI の run id 等で決める。設定画面のバージョン表示はビルド時に
  注入された値を表示する（二重に持たない）

### 5.2 リリース運用（プラットフォームごとのリリース）

`macos/v…` / `windows/v…` のタグ push を手掛りに、ワークフローを自動実行する。

1. CHANGELOG は単一ファイルのプラットフォーム別ヘッダ（`## macOS 2.0.1` / `## Windows 1.0.3`）。
   対象プラの `[Unreleased]` を確定 → リリースコミット → `git tag macos/v2.0.1` → push
2. `release.yml` はタグの接頭部分からプラットフォームを判別し、**そのプラのみ**をビルドする
   （マトリクスを組まない）
3. GitHub Release にそのプラの成果物を登録する（dmg/zip/インストーラ + CHANGELOG から生成する
   リリースノート）。版番号はプラットフォーム間での機能の横断を持たないので、リリースノートと
   overview には**機能対応状況表**（どの機能がどのプラットフォームか）を必ず添付する
4. 下流の自動化:
   - **Homebrew**: `macos/v…` タグで `rami2076/homebrew-tap` へ bump PR を自動作成（sha256 自動計算。
     `brew bump-version-pr` 等を用いる）
   - **winget**: `windows/v…` タグで manifest の PR を自動作成（wingetcreate 等を用いる。導入時）
5. hotfix はそのプラの PATCH を上げるだけで、他のプラットフォームの版番号は動かない
   （プラットフォーム別バージョンの主たる利点）

アプリ内更新通知の機能は native 版でも維持し、**v2.1.0 でフッターの更新/修復ボタンとして実装済み**
（design.md 6.8）。チェック方式は GitHub Releases API から**リダイレクト方式（方式 7）**へ変更した
（`docs/app-update-check-methods.md`。レート制限なし・失敗時は沈黙）。
更新・修復は **Homebrew 経由**（`brew update && brew upgrade --cask moost` /
`brew reinstall --cask moost`）で、バイナリの自動ダウンロード配信は行わない
（下記 5.3 の注意・URLSession 配信の隔離属性問題）

### 5.3 macOS の署名と公証

| 段階 | 署名 | 手順 |
|------|------|------|
| ベータ | ad-hoc（現状維持） | README の Gatekeeper 回避手順（xattr 除去）を継続 |
| GA | Developer ID + notarization | Apple Developer Program（年 99 ドル）。初回起動時の Gatekeeper 警告と回避手順が消える。より良い配布に近づける |

App Store 配布は対象外とする（`~/.claude` の読み取りとサブプロセス起動が困難。
App Sandbox を有効にできないため）。

dmg は arm64・x86_64 のユニバーサルバイナリ一つにまとめ、配布ミスを防ぐ
（cask の sha256 も一つにする）。

**Developer ID を買わなくても配布できるか**: できる。

- brew 経路: Homebrew は curl でダウンロードするため隔離属性（com.apple.quarantine）が
  付かない。Gatekeeper の対象にならないので、ad-hoc 署名のままでも正常に起動する。
  つまり Homebrew 経由の配布は有料アカウントがなくても可能である（現在の Moost がそう）
- GitHub Release 直接ダウンロード: ブラウザ経由のダウンロードは隔離属性が付くので
  Gatekeeper に遮断される。README の `xattr -dr com.apple.quarantine` 手順を継続するか、
  システム設定＞プライバシーとセキュリティから「とにかく開く」必要がある。
  macOS 15 では右クリックで開く手段がなくなったため、手順が見つかりにくい
- 注意: アプリ内自動更新を URLSession ダウンロードで実装すると隔離属性が付いて更新に
  失敗する恐れがある。brew 経路での更新は安全です
- Apple Silicon は有効な署名（ad-hoc でよい）を必要とする。無署名のバイナリは起動できない

### 5.4 Windows の配布（導入時）

- インストーラ: Inno Setup か WiX Burn（単一 exe）。MSIX/Store は手続きが面倒なので対象外
- 署名: Azure Trusted Signing（現 Azure Code Signing。月額課金）が EV カートより安価。
  予算が取れない場合は無署名とし、README に SmartScreen 回避手順の記載を明らかにする
- 配布: GitHub Release + winget（流通機構）

**署名なしでも配布できるか**: できる。

- 無署名 exe も動く。実行すると SmartScreen が警告する。ユーザーは「詳細情報」→
  「とにかく実行」で回避できる（警告文は強いが回避はできる）
- SmartScreen はダウンロード数・URL・証明書の評判を確認する。新規アプリは評判がゼロで、
  最初は必ず警告される。署名してもすぐ通るわけではない（評判の積み上げが必要）
- winget: 無署名のインストールパッケージも採用された実績が多い。主として上級の利用者向けの配布経路
- 自己署名は効果がなく、無署名と同じ扱いになる
- 無署名 exe はセキュリティソフトに誤検されることがある

### 5.5 サプライチェーン（依存管理）

Dart 特有の対策（design.md 8 章）はスタックごとに洗い直し、プラットフォーム別に再構成する。

| スタック | 固定 | クールダウン | 脆弱性診断 |
|----------|------|-------------|-----------|
| SPM（macOS） | `Package.resolved` をコミット。tag 依存のみ | 公開 7 日未満の tag は手動審査 | osv-scanner は SPM 未対応のため補強し README に記載 |
| NuGet（Windows） | Central Package Management + lock assets | 7 日クールダウンを中央管理で強制 | osv-scanner（NuGet 対応）/ Dependabot |
| npm（Dart リファレンス実装の mcp_server のみ） | lockfile をコミット | npm の cool-down 設定を活用 | osv-scanner / Dependabot |

## 6. 移行ロードマップ

| フェーズ | 状態 | 内容 | 完了条件 | PR / 記録 |
|---|---|---|---|---|
| A. spec 抽出 | ✅ 完了 | Dart 実装から schemas/testdata/conformance を抽出。コードは無変更 | 現行のテストが全て通る。spec 単体で読める | <code>#75</code> <code>#76</code> |
| B. macOS ポート | ✅ 完了 | 先行実装の資産を活かし Swift/AppKit で実装。conformance の検査に合格 | データ契約とコアロジックが合格（conformance 全 19 件が緑） | <code>#77</code> |
| B′. macOS UI | ✅ 完了 | Tray / ポップオーバー / 設定ウィンドウ / `osascript` によるターミナル起動 | 一覧 → メモ登録 → 復帰 の最小動線を実走（＋ 設定・注意・要約・MCP 連携まで拡張） | <code>#78</code> → v2.0.0 |
| C. macOS 切り替え | ✅ 完了 | cask 本線を Native へ（macOS シリーズの起点 v2.0.0）。Flutter 実装は archive ブランチへ移しリファレンス実装として保存（後日削除） | ユーザの移行案内が明らか。更新通知が作動する（v2.1.0 アプリ内更新ボタンで充足） | <code>#72</code> <code>#84</code> |
| D. Windows | ❔ 未対応（計画あり） | apps/windows 実装。Windows シリーズの起点 v1.0.0（自系列の初版） | winget 経由の流通に載る | <code>#73</code> |

### 6.1 進捗ログ（実装側の記録）

| 日付 | フェーズ | 結果 | 記録 |
|---|---|---|---|
| 2026-09-27 | A. spec | ✅ | `#75` `#76` |
| 2026-09-27 | B. macOS | ✅ | `#77` |
| 2026-10-04 | B′. macOS UI | ✅ | `#78` → v2.0.0-macos リリース（`#80`）。cask 本線切替（C）も同時 |
| 2026-10-14 | C. macOS | ✅ | `#84`（アプリ内更新ボタン・design.md 6.8）→ v2.1.0-macos リリース。完了条件「更新通知が作動する」を満たす
| 2026-10-14 | C. macOS | ✅ | `#85`（コピー成功アニメーション移植・設定トグル・セッション ID コピー）→ v2.2.0-macos リリース
| 2026-10-14 | C. macOS | ✅ | `#86`（コピーアイコンを既定サイズ・既定色に統一、円弧は overlay 描画）→ v2.2.1-macos リリース |
| 2026-10-21 | C. macOS | ✅ | `#87`（Kitty を復帰先ターミナルに追加。リモコン経由のタブ復帰 + 新規ウィンドウフォールバック）→ v2.3.0-macos リリース |
| 2026-10-21 | C. macOS | ✅ | `#89`（Kitty タブ復帰を実機仕様に修正: kitty.conf 由来 `listen_on` の PID 付与に対応し前面インスタンスを特定）→ v2.3.1-macos リリース |
| 2026-10-23 | C. macOS | ✅ | `#91`（Hermes エージェント対応: state.db 読み取り専用で一覧・復帰・要約。詳細版 A の Hermes 行参照）→ v2.4.0-macos リリース |
| 2026-10-23 | D. Windows | 🚧 | MoostCore の Windows ビルド基盤（Package.swift の `#if os(Windows)`、SQLite3 / CoreGraphics の条件コンパイル、CI `windows-core` ジョブ）。UI・リリースワークフローは未着手（Windows セッションで継続。`windows-handoff.md` 参照） |
| - | D. Windows | ❔ | `#73` |

> **フェーズ B の到達点**: ロードマップの完了条件は「一覧 → メモ登録 → 復帰」の最小動線の実走だが、`#77` はそのうち データ契約とコアロジック（conformance 19 件）に絞った。UI 動線は `B′`（`#78`）として残す。フェーズ B は「コア合格・UI 未完」の中間状態であり、cask 本線の切り替え（フェーズ C）はまだ行わない。

- **版番号（2026-09-27 決定・プラットフォーム別）**: macOS native は 1.10.x の系譜を引いて
  起点 = **v2.0.0**（技術スタックの全面改訂を系列内のメジャー改訂とする）。Windows は
  自系列 **v1.0.0** で初出荷（v2.x の MINOR で初登場のような不自然な継承はしない）
- **データディレクトリ**: 新アプリの保存先は **`~/.moost/v2/`**（メジャー世代に合わせ、
  Dart 世代のデータとの混同を避ける。2026-09-27 決定）。初回起動時に v2 が無く v1 が有れば
  **移行処置**（v1 一式コピー → 完了マーカーを書く → 以後 v1 は読み取り専用）。schemaVersion は
  変わらなくても形式なので上げない（データ契約の変更は別の機会）
- **同一性**: Bundle ID・cask 名（moost）は現状維持。ログイン時起動の登録（SMAppService）
  も連続性を保つ
- **Dart 実装の保守**: ベータ期間中はセキュリティのみ修正。機能追加を行わない
  （二重維持を防ぐ）。conformance 合格確認後に削除


## 7. メンテナンス方法（一貫性の保守）

複数プラットフォームになると「同じ製品」であることは単一の実装では保証されない。
次の 5 つの保守動作で一貫性を保つ。

### 7.1 データ契約（`spec/`）が単一の情報源

- `spec/` の schemas・Fixture・conformance チェックリストが唯一の正
- 各プラットフォームのテストは**同じ Fixture** を実行する。プラットフォーム別の Fixture 複製を作らない
- データ契約の変更は MAJOR 級の製品イベント: `spec/` 変更 + CHANGELOG + 7.3 のマトリクスを同時に更新する

### 7.2 conformance Suite がリリースゲート

- 各プラットフォームの conformance テストが red のとき、そのプラットフォームはリリースしない（CI ゲートで強制）
- 機能追加の流れ: `spec/conformance.md` 更新 → Fixture 追加 → 各実装（リファレンス実装の Dart が先行して他の実装を導く）
- 本番で見つバグは**まず Fixture を足す**（回帰防止）

### 7.3 機能サポートマトリクス（唯一の情報源はこの節）

きまり:

- 機能追加時には必ず行を追加する。リリースノートにはこの節の差分を転記する
- 「対応」は conformance 合格済みを意味する（「動く」ではなく「合格」）

記号: ✅ 対応済み / 🚧 対応予定（目標を示す） / ❔ 未対応（計画あり） / ― 考慮外

| 機能 | macOS（Flutter・現行 v1.10） | macOS native（v2） | Windows（保留） | Linux（保留） |
|---|---|---|---|---|
| **メモ化本体** | | | | |
| セッションからのメモ作成（sessionId・projectPath・lastPrompt を自己完結で捕捉、ADR-003） | ✅ | 🚧 v2.0.0 | 🚧 | ― |
| 編集（title / tags / body のみ可変）・削除 | ✅ | 🚧 | 🚧 | ― |
| 登録プロジェクト（セッション非依存の起動ディレクトリ、ADR-004） | ✅ | 🚧 | 🚧 | ― |
| **セッション一覧** | | | | |
| 直近セッション一覧（history.jsonl 集約） | ✅ | 🚧 | 🚧 | ― |
| フォークセッションの除外（行単位のマーカー検査） | ✅ | 🚧 | 🚧 | ― |
| セッション表題（ai-title / 先頭 50 文字フォールバック） | ✅ | 🚧 | 🚧 | ― |
| 要約（agent -p・回数制限つき） | ✅ | 🚧 | 🚧 | ― |
| **復帰** | | | | |
| ワンクリック復帰（`cd && agent --resume`） | ✅ | 🚧 | 🚧 | ― |
| シェル escape（危険な文字列への対策） | ✅ | 🚧 | 🚧 | ― |
| エージェント適配: Claude Code | ✅ | 🚧 | 🚧 | ― |
| エージェント適配: Codex | ✅ | 🚧 | 🚧 | ― |
| エージェント適配: pi | ✅ v1.10 | ✅ v2.0.0 | 🚧 | ― |
| エージェント適配: Hermes | ― | ✅ v2.4.0 | ― | ― |
| 新エージェント拡張（アダプタ登販・ADR-004） | ✅ 機構あり | 🚧 | 🚧 | ― |
| **UI** | | | | |
| システムトレイ常駐 | ✅ | 🚧 | 🚧 | ― |
| ポップアップ（一覧 + エディタ） | ✅ | 🚧 | 🚧 | ― |
| ログイン時自動起動（OS の実状態を表示） | ✅ | 🚧 | 🚧 | ― |
| 設定（端末アプリ・一覧文字数・コピーアニメーション） | ✅ | ✅ v2.2.0 | 🚧 | ― |
| 端末: Terminal.app（既定） | ✅ | 🚧 | 🚧 | ― |
| 端末: iTerm2 | ✅ | 🚧 | ― | ― |
| 端末: Kitty（リモコン・タブ） | ❔ | ✅ v2.3.1 | ― | ― |
| 端末: その他（Warp 等） | ❔ | ❔ | ― | ― |
| **データ・プラットフォーム** | | | | |
| データ契約（memos / settings / projects、schemaVersion 1） | ✅ | ✅ 継承 | 🚧 | ― |
| 保存先 `~/.moost/v2/`（初回起動時に v1 からマイグレーション） | ❔ | 🚧 | 🚧 | ― |
| MCP サーバー（読取り専用・4 ツール） | ✅ apps/mcp_server | ✅ 内蔵 `moost mcp` | 🚧 | ― |
| 更新通知（リダイレクト方式・方式 7） | ✅ v1.10（GitHub Releases API） | ✅ v2.1.0（リダイレクト方式） | 🚧 | ― |
| アプリ内更新ボタン（フッター・brew 更新/修復・design.md 6.8） | ✅ v1.10 | ✅ v2.1.0 | 🚧 | ― |
| インストール破損検知と修復（`*.upgrading` / 実行ファイル欠落） | ✅ v1.6.0〜 | ✅ v2.1.0（brew 管理下のみ） | 🚧 | ― |
| **配布** | | | | |
| Homebrew cask | ✅ v1 | ✅ v2.0.0 以降 native | ― | ― |
| ベータチャンネル（moost-beta cask） | ❔ | 🚧 フェーズ B | ― | ― |
| インストーラ | ✅ dmg | 🚧 ユニバーサル dmg | 🚧 msix + winget | ― |

#### 詳細版 A: エージェント別サポート

| エージェント | macOS（Flutter） | macOS native | Windows（保留） | Linux（保留） | 復帰コマンド | 備考 |
|---|---|---|---|---|---|---|
| Claude Code | ✅ | 🚧 v2.0.0 | 🚧 | ― | `claude --resume <sessionId>` | 詳細は下表 |
| Codex | ✅ | 🚧 | 🚧 | ― | `codex resume <sessionId>` | 詳細は下表 |
| pi | ✅ v1.10 | ✅ v2.0.0 | 🚧 | ― | `pi --session <sessionId>` | 詳細は下表 |
| Hermes | ― | ✅ v2.4.0 | ― | ― | `hermes chat --resume <id>` | 詳細は下表。native のみ |
| （新設） | 🚧 要アダプタ実装 | 🚧 | 🚧 | ― | 要定義 | AdapterRegistry に登販する機構が既にある |

エージェント別機能の詳細（リファレンス実装の正: `packages/core/lib/src/agent/`。Hermes は native のみ）:

| 能力 | Claude Code | Codex | pi | Hermes |
|---|---|---|---|---|
| 履歴読み取り | `history.jsonl`（display / timestamp[ms] / project / sessionId） | `history.jsonl`（session_id / ts[秒] / text。project は rollout の session_meta.cwd から補完） | `~/.pi/agent/sessions/**/*.jsonl` | `~/.hermes/state.db`（SQLite **読み取り専用**。WAL 対応。書き込みなし） |
| 復帰判定 | セッション JSONL の存在 | rollout JSONL の存在（消えたものは `codex resume` でも復帰不能なので一覧から除外） | セッションファイルの存在 | sessions 行の存在（`source IN ('local','oneshot')` かつ `message_count > 0`、archived/hidden 除外。CLI 起点のみ） |
| セッション表題 | ai-title（末尾 64KB） / 無ければプロンプト先頭 50 文字 | ai-title 無し → 常にプロンプト先頭 50 文字フォールバック | セッションの title（あれば） / 先頭 50 文字 | `title` 列（Hermes の自動タイトル）/ なければ最終プロンプト |
| 要約 | `claude -p` | 直近: `codex exec --ephemeral` / 全体: `codex exec resume` | ローカル抽出（API 消費なし） | state.db から抜粋してそのまま返す（ヘッドレス要約なし → ローカル抽出・API 消費ゼロ） |
| 起動検出 | PATH 自動検出 + 設定で上書き（GUI の PATH 問題対策込み） | 同左 | 同左 | PATH 自動検出（`~/.local/bin/hermes` 等。設定上書きは未実装） |

#### 詳細版 B: ターミナル別サポート（macOS）

実装の正: `terminal_launcher.dart`（Flutter）。macOS native は
`apps/macos/Sources/MoostCore/Launch.swift` の `TerminalLauncher`。
Terminal.app / iTerm2 は **osascript（AppleScript）方式**、Kitty は **リモコン方式**。
**既定対応は 2 アプリ + Kitty** で、未知のアプリ名は Terminal.app にフォールバックする。

| 端末アプリ | macOS（Flutter） | macOS native | Windows | Linux | 起動機構 | 備考 |
|---|---|---|---|---|---|---|
| Terminal.app | ✅ | 🚧 | 🚧 | ― | osascript `tell application "Terminal" … do script` | 既定。未知アプリ名のフォールバック先 |
| iTerm2 | ✅ | 🚧 | ― | ― | osascript `create window` + `write text` | 設定値は `iTerm2`（.app 無し。UI の選局肢と一致させる） |
| Kitty | ❔（値は保持） | ✅ v2.3.1 | ― | ― | `kitten @ launch --type=tab`（リモコン）→ 失敗時 `open -n -a kitty` | AppleScript 非対応のためリモコン方式。タブには kitty.conf の `allow_remote_control yes` と `listen_on unix:/tmp/moost-kitty.sock` の追記と **Kitty 再起動**が必要（listen_on はリロード非対応）。kitty.conf 由来の listen_on はソケットに PID が付くため、Moost は前面ウィンドウのオーナー PID から候補を探索（design.md 6.6 注記）。設定値は `kitty`（native のみの値。Dart は未知値として Terminal.app へフォールバック） |
| Warp / Alacritty / Ghostty 等 | ❔ | ❔ | ― | ― | 未実装 | 設定は文字列を保持するが起動は Terminal.app に落ちる（#41 の ENUM 化しない設計）。公式対応には起動機構の追加が必要 |
| Windows Terminal | ― | ― | 🚧 フェーズ D | ― | 予定 | Windows native の既定受け入れ対象 |
| Alacritty / Ghostty 等（Win/Lin） | ― | ― | ❔ | ❔ | 要調査 | Linux 自体保留のため保留 |

補足:

- 復帰コマンドのシェル escape はエージェント・端末によらず共通（conformance G1）
- native 実装は Terminal.app / iTerm2 を osascript 方式で踏襲済み（権限は Apple Events /
  Automation の受け入れが必要。初回のみ権限ダイアログ）。Kitty は AppleScript 非対応のため
  リモコン方式（ソケット経由。権限ダイアログなし）
- Windows では端末の作りが別（conhost / Windows Terminal の CLI）なので、フェーズ D でこの行を新設する
- Windows のビルド基盤（2026-10-23）: MoostCore は Foundation のみに依存するため
  Swift for Windows でビルド・テストできる（CI `windows-core`）。MoostApp（AppKit）は
  macOS 専用のため Windows では対象外。UI 方式とリリースワークフローは Windows セッションで継続

### 7.4 依存性の保守（スタック別）

| スタック | 依存の記録 | 脆弱性の診断 |
|---|---|---|
| Dart | `pubspec.lock` をコミット | osv-scanner（既設） |
| Swift / SPM | `Package.swift` で version pin | SPM audit / Dependabot |
| .NET | NuGet 中央パッケージ管理（`Directory.Packages.props`） | osv-scanner / Dependabot |

### 7.5 保守期間と文書の管理

- Flutter（Dart）実装の保守期間: native の conformance 合格・cask 本線切り替え・
  1 リリース期間の観察まで。**セキュリティリレーションズ修正のみ**供給（機能追加は入れない）
- CONTEXT / requirements / design は世代ごとに改版する。ADR は追記する（書き換えない）
- CHANGELOG は単一ファイル・プラットフォーム別の見出し（5.1）
- 復旧: native に重大な欠陥が見つかったら cask を Flutter 版へ復する。
  v2 移行後も `~/.moost/v1/` のデータは読取り専用で保存されているため復元できる

## 8. 付属文書の改版

| 文書 | 改版内容 |
|------|----------|
| RELEASE.md | 5 章に合わせ改訂（プラットフォーム別接タグ・プラットフォームごとのリリース・brew/winget 自動 PR） |
| design.md | 1 章（パッケージ構成）、6.4（Flutter 再現方針 → AppKit 本体）、8 章（依存管理をスタック別に）、9 章（テスト方針 + conformance） |
| ADR-001 | ADR-005 の Accepted 時に superseded へ |
| overview.md | フェーズ C 完了後に技術構成の記述を書き改める |

## 9. 決定事項

**決定済み（2026-09-27）**:

1. macOS = Swift/AppKit、Windows = C#/.NET + WPF …… 採用
2. MCP サーバー: **アプリ内蔵の `moost mcp` を主に**。ユーザに Node の有無を前提させない
   （アプリ単体で完結）。Dart の mcp_server はリファレンスとして残す
3. 版番号: **プラットフォーム別系列**（`macos/v…` `windows/v…`）。macOS native は 2.0.0 起点
   （1.10.x の流れを汲む）、Windows は自系列 1.0.0 で登場
4. 保存先: 新アプリは `~/.moost/v2/`。初回起動で v1 から移行処置（6 章）
5. macOS Developer ID …… 当面不要（brew 経路は現状で可）。直接配布を主流にし、URLSession
   による自動更新を実装する前に取得を判断する
6. Windows 署名 …… 当面不要（配布は可）。SmartScreen のクレームが発生したら調達を考える
7. Linux 実装 …… 保留

**未決**:

1. Flutter 実装の保存場所: `legacy/`（同居）か archive ブランチ（分離）か。
   **推しは archive ブランチ**（メインツリーが汚れないように）

## 参考

- [ADR-005 案](./adr/005-per-platform-native-over-flutter.md)
- [RELEASE.md](../../RELEASE.md)（Flutter 版のリリース運用。この手順を流用する）
- [design.md](./design.md) 7 章（既知のハマりどころ）
- Homebrew cask 運用（`rami2076/tap`）、wingetcreate 等の OSS ツール
