import SwiftUI
import MoostCore

/// 設定画面（design.md 6.6）。保存は各項目の変更時（Flutter 版と同じ）。
/// ログイン時自動起動は OS 実状態（SMAppService）を正とし、設定ファイルには持たない。
struct SettingsScreen: View {
    @EnvironmentObject var model: AppModel

    @State private var terminalApp = "Terminal.app"
    @State private var recentLimit = 20
    @State private var claudePath = ""
    @State private var piProvider = ""
    @State private var piModel = ""

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "設定") {
                model.backToList(returningTo: model.tab)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    label("復帰先ターミナル")
                    Picker("", selection: $terminalApp) {
                        Text("Terminal.app").tag("Terminal.app")
                        Text("iTerm2").tag("iTerm2")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: terminalApp) { _, value in
                        save { $0.terminalApp = value }
                    }

                    label("直近セッション表示件数（5〜100、5 刻み）")
                    HStack {
                        Text("\(recentLimit) 件")
                            .font(.system(size: 12))
                        Spacer()
                        Stepper("", value: $recentLimit, in: 5...100, step: 5)
                        .onChange(of: recentLimit) { _, value in
                            save { $0.recentSessionLimit = value }
                        }
                    }

                    label("claude コマンドのパス（要約用）")
                    TextField("空欄で自動検出", text: $claudePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            save { $0.claudePath = claudePath }
                            model.detectClaudePath()
                        }
                    Text(model.detectedClaudePath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    divider()

                    label("pi の provider（起動時に --provider を渡す）")
                    TextField("空欄で pi の既定に従う", text: $piProvider)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            save { $0.piProvider = piProvider }
                        }

                    label("pi の model（起動時に --model を渡す）")
                    TextField("空欄で pi の既定に従う", text: $piModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            save { $0.piModel = piModel }
                        }

                    divider()

                    Toggle("ログイン時に自動起動", isOn: Binding(
                        get: { model.autoLaunchEnabled },
                        set: { model.setAutoLaunch($0) }))
                        .toggleStyle(.switch)
                        .font(.system(size: 12))
                    Text("OS のログイン項目として管理されます（設定ファイルには保存しません）")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear(perform: loadFromModel)
    }

    private func divider() -> some View {
        Divider().padding(.vertical, 2)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
    }

    private func loadFromModel() {
        let s = model.settings
        terminalApp = s.terminalApp
        recentLimit = min(max(Int((Double(s.recentSessionLimit) / 5).rounded()) * 5, 5), 100)
        claudePath = s.claudePath
        piProvider = s.piProvider
        piModel = s.piModel
    }

    /// 現在の編集値を反映した Settings を保存する。
    private func save(_ mutate: (inout MoostCore.Settings) -> Void) {
        var updated = model.settings
        mutate(&updated)
        model.saveSettings(updated)
    }
}

/// 注意画面（design.md 6.1）。利用枠消費・権限・保持期間・更新タイミングを説明する。
struct NotesScreen: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "注意") {
                model.backToList(returningTo: model.tab)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    note("ターミナル操作の権限",
                         "セッションへの初回復帰時に macOS のオートメーション権限ダイアログが出ます"
                         + "（一度「許可」を選べば以後は出ません）。"
                         + "ターミナルは別ウィンドウで開きます（Terminal.app / iTerm2）。")
                    note("セッションの保持期間",
                         "セッションは Claude Code が cleanupPeriodDays（デフォルト 30 日）に"
                         + "基づいて保持します。メモを登録していても、期限切れのセッションには"
                         + "復帰できない場合があります。")
                    note("Claude 要約について",
                         "要約は claude -p（モデル: Haiku）で実行され、実行のたびに利用枠を消費します。"
                         + "「直近」はローカルで抜粋するため高速・低コスト、"
                         + "「全体」はセッション全体を読むため時間と枠を多く消費します。"
                         + "※ ネイティブ版の要約ボタンは現在準備中です。")
                    note("一覧の更新タイミング",
                         "直近セッション一覧は、アプリを開いたとき・タブを切り替えたとき・"
                         + "フォームから戻ったときに更新されます。手動リロードはなく、"
                         + "開きっぱなしの間は更新されません。")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func note(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
