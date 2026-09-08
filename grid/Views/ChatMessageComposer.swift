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
    let onBack: () -> Void
    let onAdd: () -> Void
    var onTogglePartnerPins: () -> Void = {}
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let pillHeight: CGFloat = 36

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.systemGray2)))
            }
            .accessibilityLabel("Back")

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
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary)
                        .rotationEffect(.degrees(isPhotoStripOpen ? 45 : 0))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(isPhotoStripOpen ? "Close photos" : "Add photo")
                .padding(.leading, 4)

                ChatSendField(
                    text: $text,
                    isFocused: $isFocused,
                    onSend: {
                        if canSend { onSend() }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, 8)
            }
            .frame(maxWidth: .infinity, minHeight: pillHeight, maxHeight: pillHeight)
            .background(
                Capsule()
                    .strokeBorder(Color(.systemGray4), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

#if canImport(UIKit)
/// Send does not resign. Opening a chat sets focus so the keyboard comes up.
private struct ChatSendField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
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
        field.wantsFocus = isFocused.wrappedValue
        if field.text != text {
            field.text = text
        }
        if isFocused.wrappedValue, field.window != nil, !field.isFirstResponder {
            field.becomeFirstResponder()
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, wantsFocus, !isFirstResponder {
            becomeFirstResponder()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 22)
    }
}
#endif
