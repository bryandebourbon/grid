import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Column-count zoom state for the proximity grid (pinch, double-tap cycle, long-press + drag).
/// Keeps magnification behavior in one place; GridView wires overlay cancellation callbacks.
@Observable
@MainActor
final class GridColumnZoom {
    var gridColumns = 3
    var baseColumns = 3
    var currentScale: CGFloat = 1.0
    var isScaling = false
    var isDragging = false
    var isLongPressing = false
    var longPressStarted = false
    var doubleTapDetected = false

    private(set) var lastTapTime = Date()
    private var dragStartTime = Date()

    var scrollDisabled: Bool { isScaling || isDragging }

    func previewColumns(for scale: CGFloat) -> Int {
        GridColumnZoomLogic.previewColumns(base: baseColumns, scale: scale)
    }

    func recordSingleTap() {
        lastTapTime = Date()
    }

    /// Double-tap cycles columns: 3 → 2 → 5 → 3. Optionally dismiss overlays opened within 0.3s.
    func handleDoubleTap(cancelRecentOverlay: (() -> Void)? = nil) {
        let timeSinceLastTap = Date().timeIntervalSince(lastTapTime)
        if timeSinceLastTap < 0.3 {
            cancelRecentOverlay?()
        }

        doubleTapDetected = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            doubleTapDetected = false
        }

        lastTapTime = Date()

        let target = GridColumnZoomLogic.nextDoubleTapTarget(from: gridColumns)

        haptic(.medium)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            gridColumns = target
            baseColumns = target
        }
    }

    func handleDoubleTapGesture(cancelRecentOverlay: (() -> Void)? = nil) {
        guard !isDragging, !isLongPressing else { return }
        handleDoubleTap(cancelRecentOverlay: cancelRecentOverlay)
    }

    private func handleDragZoom(_ dragValue: DragGesture.Value) {
        let timeSinceStart = Date().timeIntervalSince(dragStartTime)
        let distance = hypot(dragValue.translation.width, dragValue.translation.height)
        let velocity = timeSinceStart > 0 ? distance / timeSinceStart : 0

        if GridColumnZoomLogic.shouldIgnoreDrag(velocity: velocity) { return }

        let newColumns = GridColumnZoomLogic.columnsAfterDrag(
            base: baseColumns,
            verticalTranslation: dragValue.translation.height
        )

        if newColumns != gridColumns {
            haptic(.light)
            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8, blendDuration: 0)) {
                gridColumns = newColumns
            }
        }
    }

    var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { [self] value in
                if !isScaling {
                    isScaling = true
                    baseColumns = gridColumns
                    haptic(.light)
                }
                currentScale = value
                let newColumns = previewColumns(for: value)
                if newColumns != gridColumns {
                    haptic(.medium)
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8, blendDuration: 0)) {
                        gridColumns = newColumns
                    }
                }
            }
            .onEnded { [self] _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    baseColumns = gridColumns
                    currentScale = 1.0
                    isScaling = false
                }
                haptic(.light)
            }
    }

    var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { [self] _ in
                isLongPressing = true
                longPressStarted = true
                baseColumns = gridColumns
                haptic(.medium)
            }
    }

    var dragZoomGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { [self] value in
                guard isLongPressing || longPressStarted else { return }
                if !isDragging {
                    isDragging = true
                    dragStartTime = Date()
                    haptic(.light)
                }
                handleDragZoom(value)
            }
            .onEnded { [self] _ in
                if isDragging {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        baseColumns = gridColumns
                        isDragging = false
                        isLongPressing = false
                        longPressStarted = false
                    }
                    haptic(.light)
                } else {
                    isLongPressing = false
                    longPressStarted = false
                }
            }
    }

    private enum HapticWeight { case light, medium }

    private func haptic(_ weight: HapticWeight) {
        #if os(iOS)
        let style: UIImpactFeedbackGenerator.FeedbackStyle = weight == .light ? .light : .medium
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}
