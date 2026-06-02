import Foundation

/// Formats proximity distances for grid UI (matches legacy ProximityService behavior).
enum DistanceFormatLogic {

    static func format(meters distance: Double) -> String {
        let kilometers = distance / 1000.0

        if kilometers < 0.01 {
            return ".01km"
        } else if kilometers >= 99.0 {
            return "99km"
        } else if kilometers < 1.0 {
            let formatted = String(format: "%.2fkm", kilometers)
            return formatted.replacingOccurrences(of: "0.", with: ".")
        } else {
            return String(format: "%.0fkm", kilometers)
        }
    }
}
