import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Composer: circular back, compact pill field. Keyboard Return is Send.
struct ChatMessageComposer: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    var isPhotoStripOpen: Bool = false
    var isPartnerPinsOpen: Bool = false
    var showsPartnerPinsButton: Bool = false
    var keyboardActivation: Int = 0
    let onBack: () -> Void
    let onAdd: () -> Void
    var onTogglePartnerPins: () -> Void = {}
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ComposerHitButton(
                systemName: "chevron.left",
                tint: .white,
                background: UIColor.systemGray2,
                circular: true,
                accessibilityLabel: "Back",
                action: onBack
            )
            .frame(width: 44, height: 44)

            if showsPartnerPinsButton {
                Button(action: onTogglePartnerPins) {
                    Image(systemName: isPartnerPinsOpen ? "photo.on.rectangle.fill" : "photo.on.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isPartnerPinsOpen ? .white : .primary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(isPartnerPinsOpen ? Color.blue : Color(.systemGray5)))
                }
                .accessibilityLabel(isPartnerPinsOpen ? "Hide pinned photos" : "Show pinned photos")
                .accessibilityAddTraits(.isButton)
            }

            HStack(spacing: 4) {
                ComposerHitButton(
                    systemName: "plus",
                    rotation: isPhotoStripOpen ? .pi / 4 : 0,
                    tint: .label,
                    accessibilityLabel: isPhotoStripOpen ? "Close photos" : "Add photo",
                    action: onAdd
                )
                .frame(width: 44, height: 44)
                .padding(.leading, 2)
                .zIndex(1)

                ChatSendField(
                    text: $text,
                    isFocused: $isFocused,
                    activation: keyboardActivation,
                    onSend: {
                        if canSend { onSend() }
                    }
                )
                .focused($isFocused)
                .frame(maxWidth: .infinity)
                .padding(.trailing, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .background(
                Capsule()
                    .strokeBorder(Color(.systemGray4), lineWidth: 1)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

#if canImport(UIKit)
private struct ComposerHitButton: UIViewRepresentable {
    var systemName: String
    var rotation: CGFloat = 0
    var tint: UIColor
    var background: UIColor? = nil
    var circular: Bool = false
    var accessibilityLabel: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ComposerHitHost {
        let host = ComposerHitHost()
        host.button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        apply(to: host)
        return host
    }

    func updateUIView(_ host: ComposerHitHost, context: Context) {
        context.coordinator.action = action
        apply(to: host)
    }

    private func apply(to host: ComposerHitHost) {
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        host.button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        host.button.tintColor = tint
        host.button.backgroundColor = background
        host.button.layer.cornerRadius = circular ? 22 : 0
        host.button.clipsToBounds = circular
        host.button.transform = CGAffineTransform(rotationAngle: rotation)
        host.button.accessibilityLabel = accessibilityLabel
        host.button.isAccessibilityElement = true
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

final class ComposerHitHost: UIView {
    let button = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 44, height: 44)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }
}

/// Send does not resign. Opening a chat sets focus so the keyboard comes up.
private struct ChatSendField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var activation: Int
    var onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused, onSend: onSend)
    }

    func makeUIView(context: Context) -> ExpandingChatField {
        let field = ExpandingChatField()
        field.placeholder = "Message"
        field.borderStyle = .none
        field.returnKeyType = .send
        field.enablesReturnKeyAutomatically = true
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .vertical)
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.accessibilityIdentifier = GridUITestHarness.chatComposerIdentifier
        field.accessibilityLabel = "Message"
        return field
    }

    func updateUIView(_ field: ExpandingChatField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        context.coordinator.onSend = onSend
        let justActivated = field.activation != activation
        if justActivated {
            field.activation = activation
            field.wantsFocus = true
        }
        if isFocused.wrappedValue {
            field.wantsFocus = true
        }
        if field.text != text {
            field.text = text
        }
        if justActivated {
            field.claimFocus(from: "update")
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var isFocused: FocusState<Bool>.Binding
        var onSend: () -> Void

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, onSend: @escaping () -> Void) {
            self.text = text
            self.isFocused = isFocused
            self.onSend = onSend
        }

        @objc func changed(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSend()
            if !isFocused.wrappedValue {
                isFocused.wrappedValue = true
            }
            if textField.window != nil, !textField.isFirstResponder {
                textField.becomeFirstResponder()
            }
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !isFocused.wrappedValue {
                isFocused.wrappedValue = true
            }
        }
    }
}

private final class ExpandingChatField: UITextField {
    var wantsFocus = false
    var activation = 0

    func claimFocus(from source: String) {
        guard wantsFocus, window != nil, !isFirstResponder else { return }
        becomeFirstResponder()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        claimFocus(from: "window")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 22)
    }
}
#endif
