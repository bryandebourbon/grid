import SwiftUI

/// iMessage-style composer: circular +, pill field, circular send inside the pill.
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

    private let pillRadius: CGFloat = 18
    private let sendSize: CGFloat = 26
    private var sendInset: CGFloat { (pillRadius * 2 - sendSize) / 2 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
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

            HStack(alignment: .bottom, spacing: 4) {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary)
                        .rotationEffect(.degrees(isPhotoStripOpen ? 45 : 0))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(isPhotoStripOpen ? "Close photos" : "Add photo")
                .padding(.leading, 6)
                .padding(.bottom, 4)

                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .padding(.vertical, 8)
                    .padding(.trailing, canSend ? sendSize + sendInset - 4 : 10)
            }
            .background(
                RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                    .strokeBorder(Color(.systemGray4), lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                if canSend {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: sendSize, height: sendSize)
                            .background(Circle().fill(Color.blue))
                    }
                    .accessibilityLabel("Send message")
                    .padding(sendInset)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
