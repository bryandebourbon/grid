import Foundation

/// Presentation state for the chat overlay.
///
/// SwiftUI can apply `isPresented` and `recipientDeviceID` in the same frame and
/// fire `onChange(isPresented)` with the *previous* recipient. Keep both fields
/// in one value so open/hide always activate the person who was just tapped.
struct ChatOverlaySession: Equatable {
    var isPresented = false
    var recipientDeviceID: String?
    var openNonce = 0

    mutating func open(with deviceID: String) {
        if recipientDeviceID != deviceID || isPresented == false {
            openNonce &+= 1
        }
        recipientDeviceID = deviceID
        isPresented = true
    }

    mutating func hide() {
        isPresented = false
        recipientDeviceID = nil
    }

    /// Partner the overlay must bind to while visible. Nil when closed.
    var activePartnerDeviceID: String? {
        isPresented ? recipientDeviceID : nil
    }

    /// SwiftUI identity for the overlay. Must change whenever the partner changes
    /// so ChatView cannot keep the previous thread.
    var overlayIdentity: String? {
        guard let id = activePartnerDeviceID else { return nil }
        return "\(id)-\(openNonce)"
    }
}
