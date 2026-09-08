import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageReactionPicker: View {
    var onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(MessageReactionLogic.quickEmojis, id: \.self) { emoji in
                Button {
                    onPick(emoji)
                } label: {
                    Text(emoji)
                        .font(.title2)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React with \(emoji)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 2)
    }
}

struct MessageReactionChips: View {
    let reactions: [MessageReaction]
    let currentDeviceID: String?
    var onToggle: (String) -> Void

    var body: some View {
        let groups = MessageReactionLogic.grouped(reactions, currentDeviceID: currentDeviceID ?? "")
        if !groups.isEmpty {
            HStack(spacing: 6) {
                ForEach(groups, id: \.emoji) { group in
                    Button {
                        onToggle(group.emoji)
                    } label: {
                        HStack(spacing: 3) {
                            Text(group.emoji)
                                .font(.caption)
                            if group.count > 1 {
                                Text("\(group.count)")
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(group.includesMe
                                ? Color.blue.opacity(0.18)
                                : Color(.systemBackground))
                        )
                        .overlay {
                            Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(group.emoji) \(group.count)")
                }
            }
        }
    }
}
