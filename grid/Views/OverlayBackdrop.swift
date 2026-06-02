import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Dimmed full-screen backdrop with tap and swipe-to-dismiss (shared by profile/chat/bio overlays).
struct OverlayBackdrop: View {
    let opacity: Double
    let dismissAnimation: Animation
    let onDismiss: () -> Void

    var body: some View {
        Color.black.opacity(opacity)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                lightHaptic()
                withAnimation(dismissAnimation, onDismiss)
            }
            .gesture(swipeDismissGesture)
    }

    private var swipeDismissGesture: some Gesture {
        DragGesture()
            .onEnded { value in
                let minimumSwipeDistance: CGFloat = 80
                if abs(value.translation.height) > minimumSwipeDistance
                    || abs(value.translation.width) > minimumSwipeDistance {
                    mediumHaptic()
                    withAnimation(dismissAnimation, onDismiss)
                }
            }
    }

    private func lightHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func mediumHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
