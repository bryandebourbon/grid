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
    private var cellConsumedDoubleTap = false

    private(set) var lastTapTime = Date()
    private var dragStartTime = Date()

    var scrollDisabled: Bool { isScaling || isDragging }
    var canZoomIn: Bool { gridColumns > GridColumnZoomLogic.minColumns }
    var canZoomOut: Bool { gridColumns < GridColumnZoomLogic.maxColumns }

    func zoomIn() {
        stepColumns(by: -1)
    }

    func zoomOut() {
        stepColumns(by: 1)
    }

    private func stepColumns(by delta: Int) {
        let target = GridColumnZoomLogic.clamp(gridColumns + delta)
        guard target != gridColumns else { return }
        haptic(.medium)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            gridColumns = target
            baseColumns = target
        }
    }

    func resetPressState() {
        isLongPressing = false
        longPressStarted = false
        isDragging = false
    }

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
        guard !isDragging, !isLongPressing, !cellConsumedDoubleTap else { return }
        handleDoubleTap(cancelRecentOverlay: cancelRecentOverlay)
    }

    /// A person cell handled the double-tap (profile). Don't also cycle zoom.
    func markCellConsumedDoubleTap() {
        cellConsumedDoubleTap = true
        doubleTapDetected = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            cellConsumedDoubleTap = false
            doubleTapDetected = false
        }
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

    /// Long-press, then drag to zoom. A normal swipe is not claimed.
    var pressThenDragZoomGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { [self] value in
                switch value {
                case .second(true, let drag?):
                    let isHorizontal = abs(drag.translation.width) > abs(drag.translation.height)
                    if isHorizontal {
                        resetPressState()
                        return
                    }
                    if !isLongPressing {
                        isLongPressing = true
                        longPressStarted = true
                        baseColumns = gridColumns
                        haptic(.medium)
                    }
                    if !isDragging {
                        isDragging = true
                        dragStartTime = Date()
                        haptic(.light)
                    }
                    handleDragZoom(drag)
                default:
                    break
                }
            }
            .onEnded { [self] _ in
                if isDragging {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        baseColumns = gridColumns
                        resetPressState()
                    }
                    haptic(.light)
                } else {
                    resetPressState()
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
