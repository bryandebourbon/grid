import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// High-resolution timing for chat open/close. Search console for `[chat-open]`.
@MainActor
enum ChatOpenTrace {
    private static var origin: CFTimeInterval = 0

    static func start(_ event: String) {
        origin = CACurrentMediaTime()
        emit(event, tag: "START")
    }

    static func mark(_ event: String) {
        emit(event, tag: nil)
    }

    private static func emit(_ event: String, tag: String?) {
        let elapsed = origin == 0 ? 0 : (CACurrentMediaTime() - origin) * 1000
        let line: String
        if let tag {
            line = String(format: "+%.1fms %@ %@", elapsed, tag, event)
        } else {
            line = String(format: "+%.1fms %@", elapsed, event)
        }
        AppLog.messaging.debug("\(line, privacy: .public)")
        print("[chat-open] \(line)")
    }
}
