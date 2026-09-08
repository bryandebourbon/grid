import CoreGraphics
import Foundation

enum GridPhotoShape: String, CaseIterable {
    case card
    case square
    case circle

    var next: GridPhotoShape {
        switch self {
        case .card: return .square
        case .square: return .circle
        case .circle: return .card
        }
    }

    var usesSquareProportion: Bool { self != .card }
    var usesCircleClip: Bool { self == .circle }

    var systemImage: String {
        switch self {
        case .card: return "rectangle.portrait.fill"
        case .square: return "square.fill"
        case .circle: return "circle.fill"
        }
    }

    var accessibilityName: String {
        switch self {
        case .card: return "Trading card"
        case .square: return "Square"
        case .circle: return "Circle"
        }
    }

    static func stored(defaults: UserDefaults = .standard) -> GridPhotoShape {
        if let raw = defaults.string(forKey: defaultsKey), let shape = GridPhotoShape(rawValue: raw) {
            return shape
        }
        if defaults.object(forKey: "squarePhotos") as? Bool == true { return .square }
        if defaults.object(forKey: "circularPhotos") as? Bool == true { return .circle }
        return .card
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    private static let defaultsKey = "grid.photoShape"
}

/// Grid cell aspect: portrait cards are 1.6 tall for every 1 wide.
enum GridCellLayout {
    static let portraitHeightToWidth: CGFloat = 1.6
    static let gutter: CGFloat = 8
    static let cornerRadius: CGFloat = 14
    /// TEMP: 1.5× crop so current circle-framed photos look better in rounded rects. Delete later.
    static let temporaryPhotoZoom: CGFloat = 1.5

    /// SwiftUI `aspectRatio` is width / height. Square and circle stay 1∶1.
    static func widthOverHeight(square: Bool) -> CGFloat {
        square ? 1 : 1 / portraitHeightToWidth
    }
}
