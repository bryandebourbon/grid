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

extension View {
    /// Left or right edge swipe, matching chat-thread back. Used to close the chats sheet.
    func horizontalEdgeDismiss(enabled: Bool = true, bottomInset: CGFloat = 0, onDismiss: @escaping () -> Void) -> some View {
        overlay(alignment: .leading) {
            if enabled {
                HorizontalEdgeDismissStrip(isBackSwipe: { $0 > 70 }, onDismiss: onDismiss)
                    .padding(.bottom, bottomInset)
            }
        }
        .overlay(alignment: .trailing) {
            if enabled {
                HorizontalEdgeDismissStrip(isBackSwipe: { $0 < -70 }, onDismiss: onDismiss)
                    .padding(.bottom, bottomInset)
            }
        }
    }
}

private struct HorizontalEdgeDismissStrip: View {
    let isBackSwipe: (CGFloat) -> Bool
    let onDismiss: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 36)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let isMostlyHorizontal = abs(value.translation.width) > abs(value.translation.height)
                        if isMostlyHorizontal && isBackSwipe(value.translation.width) {
                            onDismiss()
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}
