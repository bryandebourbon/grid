import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct InterestSearchView: View {
    @ObservedObject var viewModel: GridViewModel
    @Environment(\.dismiss) var dismiss
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
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search interests...", text: $searchText)
                        .focused($searchFieldFocused)
                        .textFieldStyle(PlainTextFieldStyle())
                        .textInputAutocapitalization(.words)
                        .submitLabel(.search)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if canAddSearchInterest {
                            addMissingInterestCard
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 12) {
                            ForEach(filteredInterests) { interest in
                                let alreadyPicked = InterestPageStore.contains(interest, in: viewModel.interestPages)
                                SearchableInterestButton(
                                    interest: interest,
                                    isSelected: alreadyPicked,
                                    isUserInterest: viewModel.currentUserProfile?.interests.contains(interest) ?? false
                                ) {
                                    guard alreadyPicked || viewModel.canAddInterestPage else { return }
                                    viewModel.openInterestPage(interest)
                                    dismiss()
                                }
                                .opacity(alreadyPicked || viewModel.canAddInterestPage ? 1 : 0.45)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Search Interests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    searchFieldFocused = true
                }
            }
        }
        .navigationViewStyle(.stack)
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
                dismiss()
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
