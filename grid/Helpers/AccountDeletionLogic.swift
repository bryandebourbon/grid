import CloudKit
import Foundation

enum AccountDeletionLogic {
    /// CloudKit schema gaps (no type, no query index) should not block account deletion.
    static func isSkippableSchemaError(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        if text.contains("not marked indexable") { return true }
        if text.contains("did not find record type") { return true }
        if text.contains("record type") && text.contains("not found") { return true }
        if let ckError = error as? CKError {
            switch ckError.code {
            case .unknownItem, .invalidArguments:
                return true
            default:
                break
            }
        }
        return false
    }
}
