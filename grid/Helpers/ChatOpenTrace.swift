import Foundation

/// Chat open/close hook. Left silent so it does not add input latency.
@MainActor
enum ChatOpenTrace {
    static func start(_ event: String) {}
    static func mark(_ event: String) {}
}
