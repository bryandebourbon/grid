import SwiftUI

/// Asks which group to star into when more than Favorites exists.
struct StarGroupPickerView: View {
    let displayName: String
    let isInFavorites: Bool
    let groups: [PeopleGroup]
    let isInGroup: (UUID) -> Bool
    var onToggleFavorites: () -> Void
    var onToggleGroup: (UUID) -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Star \(displayName)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Button("Done", action: onDone)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            groupRow(title: "Favorites", selected: isInFavorites, action: onToggleFavorites)

            ForEach(groups) { group in
                groupRow(title: group.name, selected: isInGroup(group.id)) {
                    onToggleGroup(group.id)
                }
            }
        }
        .frame(minWidth: 260)
        .padding(.bottom, 8)
    }

    private func groupRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.yellow)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StarGroupPopoverModifier: ViewModifier {
    @ObservedObject var viewModel: GridViewModel
    let deviceID: String

    func body(content: Content) -> some View {
        content.popover(
            isPresented: Binding(
                get: { viewModel.pendingStarDeviceID == deviceID },
                set: { if !$0 { viewModel.pendingStarDeviceID = nil } }
            )
        ) {
            StarGroupPickerView(
                displayName: ProfileDisplayNameLogic.chatTitle(
                    recipientDeviceID: deviceID,
                    currentDeviceID: viewModel.currentUserProfile?.deviceID ?? "",
                    gridNodes: viewModel.allGridNodes
                ),
                isInFavorites: viewModel.starredUsers.contains(viewModel.getUserID(forDeviceID: deviceID) ?? ""),
                groups: viewModel.customGroups,
                isInGroup: { viewModel.isInCustomGroup($0, deviceID: deviceID) },
                onToggleFavorites: { viewModel.toggleStar(for: deviceID) },
                onToggleGroup: { viewModel.toggleMembership(deviceID: deviceID, groupID: $0) },
                onDone: { viewModel.pendingStarDeviceID = nil }
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

extension View {
    func starGroupPopover(viewModel: GridViewModel, deviceID: String) -> some View {
        modifier(StarGroupPopoverModifier(viewModel: viewModel, deviceID: deviceID))
    }
}
