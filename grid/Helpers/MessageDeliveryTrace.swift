import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Filterable step log for message delivery. Search the console for `[msg-test]`.
enum MessageDeliveryTrace {
    static let prefix = "[msg-test]"

    static func log(_ step: String) {
        let line = "\(prefix) \(step)"
        AppLog.messaging.debug("\(line, privacy: .public)")
        print(line)
    }

    static func start(_ label: String) {
        log("START \(label)")
    }
}

/// Accumulates one live or simulated delivery-suite run for the on-screen report.
struct MessageDeliverySuiteReport {
    struct Step: Equatable {
        var name: String
        var ok: Bool
        var detail: String
        var milliseconds: Int
    }

    var steps: [Step] = []

    mutating func add(name: String, ok: Bool, detail: String, milliseconds: Int = 0) {
        let step = Step(name: name, ok: ok, detail: detail, milliseconds: milliseconds)
        steps.append(step)
        let mark = ok ? "OK" : "FAIL"
        let timing = milliseconds > 0 ? " \(milliseconds)ms" : ""
        let extra = detail.isEmpty ? "" : " \(detail)"
        MessageDeliveryTrace.log("\(steps.count) \(name) \(mark)\(timing)\(extra)")
    }

    var allPassed: Bool { steps.contains(where: { !$0.ok }) == false && steps.isEmpty == false }

    var summary: String {
        guard steps.isEmpty == false else { return "No steps ran." }
        let lines = steps.enumerated().map { index, step in
            let mark = step.ok ? "OK" : "FAIL"
            let timing = step.milliseconds > 0 ? " \(step.milliseconds)ms" : ""
            let extra = step.detail.isEmpty ? "" : " — \(step.detail)"
            return "\(index + 1). \(step.name) \(mark)\(timing)\(extra)"
        }
        let header = allPassed ? "Message delivery test passed." : "Message delivery test had failures."
        return ([header] + lines + ["Filter Xcode for [msg-test]"]).joined(separator: "\n")
    }
}

/// Tiny JPEG used by the live image ping so we don't need the photo library.
enum MessageDeliveryTestImage {
    static func jpeg() -> Data {
        #if canImport(UIKit)
        return ProfileCreationLogic.placeholderPhotoJPEG()
        #else
        return Data([0xFF, 0xD8, 0xFF, 0xD9])
        #endif
    }
}
