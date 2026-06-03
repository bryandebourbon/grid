import SwiftUI

struct GridInterestBrowseSection: View {
    @ObservedObject var viewModel: GridViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Browse All Interests")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Tap to filter")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SearchInterestsButton {
                        viewModel.showingInterestSearch = true
                    }

                    ForEach(Interest.allCases) { interest in
                        InterestPillButton(
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
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
