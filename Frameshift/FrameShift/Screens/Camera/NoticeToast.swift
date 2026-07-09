import SwiftUI

/// White pill notice for app-chrome events (Photos permission denied, capture
/// failure) — visually consistent with TipBanner's coaching-tip style, but a
/// separate component since TipBanner is driven by CompositionCoach state and
/// lives in the viewfinder's own overlay slot.
struct NoticeToast: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .onTapGesture { if actionTitle == nil { onDismiss() } }
    }
}
