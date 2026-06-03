import Foundation
import os

/// Release-safe logging shim.
///
/// Unqualified `print(...)` in the app target is a no-op in release builds (see below).
/// Prefer `AppLog` categories for structured debug logging at important lifecycle points.
enum AppLog {
    static let subsystem = "com.bryandebourbon.grid"

    static let session = Logger(subsystem: subsystem, category: "session")
    static let grid = Logger(subsystem: subsystem, category: "grid")
    static let messaging = Logger(subsystem: subsystem, category: "messaging")
    static let stories = Logger(subsystem: subsystem, category: "stories")
    static let album = Logger(subsystem: subsystem, category: "album")
    static let proximity = Logger(subsystem: subsystem, category: "proximity")
}

@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    Swift.print(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
    #endif
}
