import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

enum ProfileCreationLogic {
    static func userFacingCloudKitError(accountStatus: CKAccountStatus, saveError: Error?) -> String {
        if let saveError {
            let ns = saveError as NSError
            if ns.domain == CKError.errorDomain,
               ns.code == CKError.notAuthenticated.rawValue {
                return "Sign in to iCloud in Settings, then try Create Profile again."
            }
            return saveError.localizedDescription
        }
        switch accountStatus {
        case .available:
            return "CloudKit did not save the profile."
        case .noAccount:
            return "Sign in to iCloud in Settings, then try Create Profile again."
        case .restricted:
            return "iCloud is restricted on this device."
        case .couldNotDetermine:
            return "Could not reach iCloud. Check the simulator network and try again."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Try again in a moment."
        @unknown default:
            return "iCloud is not available."
        }
    }

    #if canImport(UIKit)
    static func placeholderPhotoJPEG() -> Data {
        let size = CGSize(width: 400, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.85) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let initials = "TP" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 120, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = initials.size(withAttributes: attributes)
            initials.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attributes
            )
        }
    }
    #endif
}
