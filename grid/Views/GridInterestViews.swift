import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct FilterChip: View {
    let text: String
    let icon: String?
    let color: Color
    let emoji: String?
    var isFocused: Bool = false
    var onSelect: (() -> Void)?
    let onRemove: () -> Void
    
    init(
        text: String,
        icon: String? = nil,
        color: Color,
        emoji: String? = nil,
        isFocused: Bool = false,
        onSelect: (() -> Void)? = nil,
        onRemove: @escaping () -> Void
    ) {
        self.text = text
        self.icon = icon
        self.color = color
        self.emoji = emoji
        self.isFocused = isFocused
        self.onSelect = onSelect
        self.onRemove = onRemove
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Button {
                onSelect?()
            } label: {
                HStack(spacing: 4) {
                    if let emoji = emoji {
                        Text(emoji)
                            .font(.caption)
                    } else if let icon = icon {
                        Image(systemName: icon)
                            .font(.caption)
                    }

                    Text(text)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isFocused ? color.opacity(0.28) : color.opacity(0.1))
        .foregroundColor(color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(isFocused ? 0.7 : 0.3), lineWidth: isFocused ? 1.5 : 1)
        )
    }
}

// MARK: - Editable Interest Button for Profile Editing

struct EditableInterestButton: View {
    let interest: Interest
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(interest.emoji)
                    .font(.system(size: 12))
                Text(interest.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Search Interests Button for Magnifying Glass

struct SearchInterestsButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                Text("Search")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray5))
            .foregroundColor(.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Interest Pill Button for Main Grid Filter

struct InterestPillButton: View {
    let interest: Interest
    let isSelected: Bool
    let isUserInterest: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(interest.emoji)
                    .font(.system(size: 12))
                Text(interest.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                
                // Show user indicator if this is one of the user's interests
                if isUserInterest {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
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

// MARK: - Maps-style interest chrome

struct MapsStyleInterestSearchBar: View {
    var placeholder: String = "Search interests"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(placeholder)
    }
}

struct MapsInterestCircleButton: View {
    let interest: Interest
    let isSelected: Bool
    let isUserInterest: Bool
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 4 : 6) {
                ZStack {
                    Circle()
                        .fill(circleColor)
                        .frame(width: 58, height: 58)
                    Text(interest.emoji)
                        .font(.system(size: 26))
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 3)
                            .frame(width: 58, height: 58)
                    }
                }
                .shadow(color: circleColor.opacity(0.35), radius: isSelected ? 6 : 0, y: 2)

                Text(interest.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(compact ? 1 : 2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72, height: compact ? 16 : 32, alignment: .top)

                if !compact {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 72)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(interest.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var subtitle: String {
        if isSelected { return "Filtered" }
        if isUserInterest { return "Yours" }
        return " "
    }

    private var circleColor: Color {
        InterestMapsChrome.circleColor(for: interest)
    }
}

enum InterestMapsChrome {
    static func circleColor(for interest: Interest) -> Color {
        let groups: [(Set<Interest>, Color)] = [
            ([.technology, .programming, .startups], Color(red: 0.20, green: 0.48, blue: 0.96)),
            ([.gaming], Color(red: 0.56, green: 0.27, blue: 0.93)),
            ([.fitness, .running, .cycling, .hiking, .swimming], Color(red: 0.20, green: 0.72, blue: 0.45)),
            ([.yoga, .meditation, .spirituality], Color(red: 0.62, green: 0.40, blue: 0.90)),
            ([.art, .design, .photography, .dancing], Color(red: 0.96, green: 0.38, blue: 0.55)),
            ([.music, .concerts, .theater], Color(red: 0.95, green: 0.36, blue: 0.38)),
            ([.writing, .books, .education, .languages], Color(red: 0.95, green: 0.62, blue: 0.18)),
            ([.cooking, .coffee, .wine, .foodie], Color(red: 0.96, green: 0.52, blue: 0.18)),
            ([.travel, .outdoors, .gardening], Color(red: 0.18, green: 0.62, blue: 0.72)),
            ([.fashion, .nightlife, .gay, .lgbtq], Color(red: 0.91, green: 0.28, blue: 0.55)),
            ([.business, .investing, .networking], Color(red: 0.95, green: 0.78, blue: 0.20)),
            ([.movies, .comedy], Color(red: 0.38, green: 0.42, blue: 0.90)),
            ([.sports], Color(red: 0.22, green: 0.68, blue: 0.38)),
            ([.volunteering, .pets], Color(red: 0.95, green: 0.32, blue: 0.42))
        ]
        for (group, color) in groups where group.contains(interest) {
            return color
        }
        return Color(red: 0.48, green: 0.50, blue: 0.62)
    }
}

// MARK: - Interest Search View

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

// MARK: - Selected Interest Chip for "Pile Up" Display

struct SelectedInterestChip: View {
    let interest: Interest
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(interest.emoji)
                .font(.system(size: 12))
            Text(interest.rawValue)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue)
        .foregroundColor(.white)
        .clipShape(Capsule())
    }
}

// MARK: - Searchable Interest Button

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
