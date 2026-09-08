import SwiftUI
#if canImport(UIKit)
import UIKit

/// UIKit control so XCTest taps actually fire on iOS 27. SwiftUI `Button` +
/// `accessibilityIdentifier` is visible to XCTest but often does not receive the
/// synthesized touch on a physical device.
struct UITestHitButton: UIViewRepresentable {
    let title: String
    let identifier: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = title
        button.isAccessibilityElement = true
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = identifier
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}
#endif
