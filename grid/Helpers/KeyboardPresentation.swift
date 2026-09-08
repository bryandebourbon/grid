import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Chat-only keyboard helpers. Grid never keeps first responder.
@MainActor
enum KeyboardPresentation {
    private static let heightDefaultsKey = "chatKeyboardOverlapHeight"
    private static let fallbackHeight: CGFloat = 336

    static var overlapHeight: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: heightDefaultsKey)
            return stored > 80 ? stored : fallbackHeight
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: heightDefaultsKey)
            KeyboardOverlapState.shared.height = newValue
        }
    }

    static func installHeightObserver() {
        #if os(iOS)
        guard heightObserver == nil else { return }
        heightObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { notification in
            recordHeight(from: notification)
        }
        #endif
    }

    static func dismissKeyboard() {
        ChatOpenTrace.mark("keyboard.dismiss")
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    #if os(iOS)
    private static var heightObserver: NSObjectProtocol?

    private static func recordHeight(from notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = max(0, UIScreen.main.bounds.height - frame.minY)
        if overlap > 80 {
            overlapHeight = overlap
            ChatOpenTrace.mark("keyboard.height \(Int(overlap))")
        }
    }
    #endif
}

@MainActor
final class KeyboardOverlapState: ObservableObject {
    static let shared = KeyboardOverlapState()
    @Published var height: CGFloat = KeyboardPresentation.overlapHeight
}
