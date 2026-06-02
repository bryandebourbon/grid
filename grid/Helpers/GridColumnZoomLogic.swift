import Foundation

/// Pure column-zoom math used by `GridColumnZoom` (testable without SwiftUI gestures).
enum GridColumnZoomLogic {
    static let minColumns = 2
    static let maxColumns = 5
    static let doubleTapCycle: [Int: Int] = [3: 2, 2: 5]
    static let fastSwipeVelocityThreshold: CGFloat = 400
    static let dragSensitivity: CGFloat = 100

    /// Double-tap cycle: 3 → 2 → 5 → 3 (any other current value resets to 3).
    static func nextDoubleTapTarget(from current: Int) -> Int {
        doubleTapCycle[current] ?? 3
    }

    /// Pinch preview: scale below 1 increases column count (more cells); scale above 1 decreases it, clamped to 2…5.
    static func previewColumns(base: Int, scale: CGFloat) -> Int {
        let scaleThreshold: CGFloat = 0.25
        let columnDelta = Int((1.0 - scale) / scaleThreshold)
        return clamp(base + columnDelta)
    }

    static func columnsAfterDrag(base: Int, verticalTranslation: CGFloat) -> Int {
        let verticalDelta = -verticalTranslation
        let columnChange = Int(verticalDelta / dragSensitivity)
        return clamp(base + columnChange)
    }

    static func shouldIgnoreDrag(velocity: CGFloat) -> Bool {
        velocity > fastSwipeVelocityThreshold
    }

    static func clamp(_ columns: Int) -> Int {
        max(minColumns, min(maxColumns, columns))
    }
}
