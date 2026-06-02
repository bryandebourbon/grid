import Foundation

/// Release-safe logging shim.
///
/// This module-scoped `print` shadows the Swift standard library's global
/// `print` for every unqualified `print(...)` call within the app target. In
/// **release** builds it compiles to a no-op, so verbose debug logging — which
/// throughout this app includes device IDs, CloudKit record names, user IDs,
/// and message metadata — never reaches the production device console. In
/// **debug** builds it forwards to `Swift.print` unchanged.
///
/// This is a pragmatic, zero-risk way to keep PII and noise out of production
/// logs without rewriting hundreds of existing call sites. New code that needs
/// structured, queryable logging should prefer `os.Logger` directly (see
/// `CryptoService`/`PrivacyService`). If you ever need stdout output in a
/// release build, call `Swift.print(...)` explicitly.
@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    Swift.print(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
    #endif
}
