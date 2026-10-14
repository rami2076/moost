import SwiftUI
import MoostCore

/// コピー操作のボタン（Flutter 版 `CopyIconButton` の native 移植）。
///
/// 成功すると
/// 1. アイコンの円周を緑の線が時計回りに一周し（スイープ・250ms）
/// 2. 描き終わるとアイコンが緑のチェックマークに変わり
/// 3. しばらくして元に戻る（スナックバーは出さない）。
///
/// OS の「視差効果を減らす」（reduce motion）有効時や設定 `copyAnimation` が
/// OFF のときはスイープを省略して直ちにチェックマークを出す
/// （Dart の `CopyFeedbackTiming` と同じ扱い）。フィードバック中の連打は無視する。
struct CopyButton: View {
    /// 設定 `copyAnimation`（false ならスイープなしで即チェック表示）。
    var copyAnimation = true
    /// nil ならアイコンのみ（一覧行・MetaPanel 等）。
    var label: String? = nil
    /// 実際のコピー処理（success/failure はこの View では判定しない）。
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .idle
    @State private var progress: CGFloat = 0
    @State private var resetTask: Task<Void, Never>?

    enum Phase: Equatable {
        case idle, sweep, checked
    }

    // Dart CopyFeedbackTiming の既定値（sweepMs=250 / holdMs=400 / noAnimationHold=1000）
    private static let sweepDuration: TimeInterval = 0.25
    private static let holdDuration: TimeInterval = 0.4
    private static let noAnimationHold: TimeInterval = 1.0

    /// 円弧の直径。アイコン（既定フォントサイズ ~14pt）の周囲に少し余白を取る。
    /// **レイアウトには影響しない**（overlay で描画。隣のアイコンとサイズ・間隔を揃えるため）。
    private static let arcSize: CGFloat = 22

    var body: some View {
        Button(action: handleTap) {
            if let label {
                Label {
                    Text(label)
                } icon: {
                    icon
                }
            } else {
                icon
            }
        }
        .buttonStyle(.borderless)
        .onDisappear {
            resetTask?.cancel()
            resetTask = nil
            phase = .idle
            progress = 0
        }
    }

    private var icon: some View {
        Image(systemName: phase == .checked ? "checkmark" : "doc.on.doc")
            .fontWeight(phase == .checked ? .semibold : .regular)
            .foregroundStyle(phase == .checked ? Color.green : Color.primary)
            // 円弧は overlay で描く（レイアウトサイズを変えないため。条件挿入だと
            // 最初の描画に最終値が使われてスイープがアニメしない）。
            .overlay {
                Circle()
                    .trim(from: 0, to: phase == .sweep ? progress : (phase == .checked ? 1 : 0))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: Self.arcSize, height: Self.arcSize)
                    .opacity(phase == .idle ? 0 : 1)
            }
    }

    private func handleTap() {
        // フィードバック中の連打は無視（Dart の _busy と同じ）
        guard phase == .idle else { return }
        action()
        if reduceMotion || !copyAnimation {
            phase = .checked
            scheduleReset(after: Self.noAnimationHold)
            return
        }
        resetTask?.cancel()
        phase = .sweep
        progress = 0
        withAnimation(.linear(duration: Self.sweepDuration)) {
            progress = 1
        }
        scheduleReset(after: Self.sweepDuration, then: Self.holdDuration)
    }

    /// スイープ完了後にチェックへ、さらに保持時間後に idle へ。
    private func scheduleReset(after sweep: TimeInterval, then hold: TimeInterval) {
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(sweep))
            guard !Task.isCancelled else { return }
            phase = .checked
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            phase = .idle
            progress = 0
        }
    }

    /// アニメーションなし版: チェック表示を長めに見せてから idle へ。
    private func scheduleReset(after hold: TimeInterval) {
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            phase = .idle
            progress = 0
        }
    }
}
