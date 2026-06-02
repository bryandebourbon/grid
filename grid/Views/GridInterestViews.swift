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
    let onRemove: () -> Void
    
    init(text: String, icon: String? = nil, color: Color, emoji: String? = nil, onRemove: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.color = color
        self.emoji = emoji
        self.onRemove = onRemove
    }
    
    var body: some View {
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
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
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

// MARK: - Interest Search View

struct InterestSearchView: View {
    @ObservedObject var viewModel: GridViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    
    // Computed property for filtered interests based on search
    private var filteredInterests: [Interest] {
        if searchText.isEmpty {
            return Interest.allCases
        } else {
            return Interest.allCases.filter { interest in
                interest.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search interests...", text: $searchText)
                            .focused($searchFieldFocused)
                            .textFieldStyle(PlainTextFieldStyle())
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Selected interests "pile up" display
                    if !viewModel.selectedInterestFilter.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Filters (\(viewModel.selectedInterestFilter.count))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(viewModel.selectedInterestFilter), id: \.self) { interest in
                                        SelectedInterestChip(interest: interest) {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                viewModel.removeInterestFilter(interest)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(10)
                    }
                }
                .padding()
                
                Divider()
                
                // Search results or all interests
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 12) {
                        ForEach(filteredInterests) { interest in
                            SearchableInterestButton(
                                interest: interest,
                                isSelected: viewModel.selectedInterestFilter.contains(interest),
                                isUserInterest: viewModel.currentUserProfile?.interests.contains(interest) ?? false
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.toggleInterestFilter(interest)
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Search Interests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.selectedInterestFilter.isEmpty {
                        Button("Clear All") {
                            viewModel.clearInterestFilter()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                searchFieldFocused = true
            }
        }
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
