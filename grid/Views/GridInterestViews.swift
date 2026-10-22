import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct InterestSearchView: View {
    @ObservedObject var viewModel: GridViewModel
    var isActive: Bool
    var onClose: () -> Void
    @State private var searchText = ""
    @State private var newInterestEmoji = "✨"
    @FocusState private var searchFieldFocused: Bool

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredInterests: [Interest] {
        if trimmedSearch.isEmpty {
            return Interest.allCases
        }
        return Interest.allCases.filter { interest in
            interest.rawValue.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private var canAddSearchInterest: Bool {
        !trimmedSearch.isEmpty && filteredInterests.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                Text("Search")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Search interests", text: $searchText)
                    .focused($searchFieldFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if canAddSearchInterest {
                        addMissingInterestCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }
                    ForEach(filteredInterests) { interest in
                        interestRow(interest)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .onChange(of: isActive) { active in
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if isActive { searchFieldFocused = true }
                }
            } else {
                searchFieldFocused = false
                searchText = ""
            }
        }
    }

    private func interestRow(_ interest: Interest) -> some View {
        let alreadyPicked = InterestPageStore.contains(interest, in: viewModel.interestPages)
        let canChoose = alreadyPicked || viewModel.canAddInterestPage
        return Button {
            guard canChoose else { return }
            viewModel.openInterestPage(interest)
            onClose()
        } label: {
            HStack(spacing: 14) {
                Text(interest.emoji)
                    .font(.title3)
                    .frame(width: 32)
                Text(interest.rawValue)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if alreadyPicked {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(canChoose ? 1 : 0.4)
        .accessibilityLabel(interest.rawValue)
    }

    private var addMissingInterestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No matches for “\(trimmedSearch)”")
                .font(.subheadline.weight(.medium))

            Text("Add it and pick an emoji")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                ForEach(CustomInterestStore.emojiPalette, id: \.self) { emoji in
                    Button {
                        newInterestEmoji = emoji
                    } label: {
                        Text(emoji)
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                newInterestEmoji == emoji
                                    ? Color.blue.opacity(0.2)
                                    : Color(.systemGray6)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                viewModel.addCustomInterest(named: trimmedSearch, emoji: newInterestEmoji)
                searchText = ""
                newInterestEmoji = "✨"
                onClose()
            } label: {
                Label("Add \(trimmedSearch)", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SearchableInterestButton: View {
    let interest: Interest
    let isSelected: Bool
    let isUserInterest: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(interest.emoji)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(interest.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    if isUserInterest {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text("Your Interest")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .blue)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isUserInterest {
            return Color.blue.opacity(0.1)
        } else {
            return Color(.systemBackground)
        }
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isUserInterest {
            return .blue
        } else {
            return .primary
        }
    }

    private var borderColor: Color {
        if isSelected {
            return .blue
        } else if isUserInterest {
            return .blue.opacity(0.5)
        } else {
            return Color(.systemGray4)
        }
    }
}
