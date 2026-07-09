import SwiftUI

/// White pill coaching tip — matches iOS Camera Portrait mode coaching style.
/// Dark text on white background, capsule shape.
struct TipBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .onTapGesture { onDismiss() }
    }
}
