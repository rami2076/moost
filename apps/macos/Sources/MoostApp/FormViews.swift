import SwiftUI
import MoostCore

/// メモ登録フォーム（design.md 6.3-1: 入口のセッションを見失わない）。
/// 元セッションのメタ情報（エージェント・プロジェクト・ID・日時・最終発言）を
/// 「このメモの元セッション」1 ブロックに統合して上部に固定し、
/// タイトル / タグ / 本文を左揃えで入力（6.3-2）。
struct NewMemoScreen: View {
    let session: RecentSession
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "メモを登録")

            InlineSessionDetail(session: session)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("タイトル")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("タイトル", text: $model.draftTitle)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("タグ（カンマ区切り）")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("タグ（カンマ区切り）", text: $model.draftTags)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("本文")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.draftBody)
                        .font(.system(size: 12))
                        .frame(minHeight: 120)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // フォーム下部のボタン（ScrollView と混ぜず固定）
            HStack {
                Button("キャンセル") { model.cancelNewMemo() }
                Spacer()
                Button("保存") { model.saveNewMemo(for: session) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.draftTitle
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

/// メモ編集フォーム（更新 + 削除 + ターミナル再開）。
struct EditMemoScreen: View {
    let memo: Memo
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "メモを編集")

            MetaPanel(
                agentId: memo.agent,
                projectPath: memo.projectPath,
                sessionId: memo.sessionId,
                updatedAt: memo.updatedAt)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("タイトル")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("タイトル", text: $model.editTitle)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("タグ（カンマ区切り）")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("タグ（カンマ区切り）", text: $model.editTags)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("本文")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.editBody)
                        .font(.system(size: 12))
                        .frame(minHeight: 110)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if model.deleteConfirmVisible {
                HStack {
                    Text("このメモを削除しますか？")
                        .font(.system(size: 12))
                    Spacer()
                    Button("キャンセル") { model.deleteConfirmVisible = false }
                        .buttonStyle(.borderless)
                    Button("削除") { model.deleteMemo(memo) }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            HStack {
                Button {
                    model.resumeFromMemo(memo)
                } label: {
                    Label("ターミナルで再開", systemImage: "terminal")
                }
                Spacer()
                if !model.deleteConfirmVisible {
                    Button("削除") { model.deleteConfirmVisible = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                Button("戻る") { model.backToList(returningTo: .memos) }
                Button("保存") { model.updateMemo(memo) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.editTitle
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

/// メタ情報パネル（エージェント・プロジェクト・セッション ID・日時）。
struct MetaPanel: View {
    let agentId: String
    let projectPath: String
    let sessionId: String
    let updatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                AgentBadge(agentId: agentId)
                Text(projectPath.isEmpty ? "(パス不明)" : projectPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(sessionId)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(AppFormat.dateTime(updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}

/// インレインのセッション詳細（メモ登録フォーム内の重ね表示。6.3-2）。
/// メタ情報のみ。要約はセッション詳細画面（info アイコン）から行う。
struct InlineSessionDetail: View {
    let session: RecentSession
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("このメモの元セッション")
                .font(.system(size: 11, weight: .medium))
            HStack(spacing: 6) {
                AgentBadge(agentId: session.agentId)
                Text(session.projectPath.isEmpty ? "(パス不明)" : session.projectPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text("ID: \(session.sessionId)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(AppFormat.dateTime(session.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text("最後のあなたの発言: \(session.lastPrompt)")
                .font(.system(size: 11))
                .lineLimit(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
