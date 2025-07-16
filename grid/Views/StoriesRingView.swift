import SwiftUI

struct StoriesRingView: View {
    let hasStories: Bool
    let hasUnviewedStories: Bool
    let isCurrentUser: Bool
    let size: CGFloat
    
    private var ringGradient: LinearGradient {
        if isCurrentUser {
            // Blue gradient for current user
            return LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if hasUnviewedStories {
            // Instagram-style gradient for unviewed stories
            return LinearGradient(
                colors: [Color.orange, Color.pink, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // Gray for viewed stories
            return LinearGradient(
                colors: [Color.gray, Color.gray],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var ringWidth: CGFloat {
        size * 0.06 // Slightly thinner ring (6% instead of 8%)
    }
    
    // Calculate the circle size so that the stroke stays within bounds
    private var circleSize: CGFloat {
        // Reduce the circle size by the ring width so the stroke doesn't extend beyond the cell
        size - ringWidth
    }
    
    var body: some View {
        // Show ring only if user has stories AND there are unviewed stories
        // (applies to both current user and other users)
        if hasStories && hasUnviewedStories {
            Circle()
                .stroke(ringGradient, lineWidth: ringWidth)
                .frame(width: circleSize, height: circleSize)
        } else {
            // No ring when no stories or all stories are viewed
            EmptyView()
        }
    }
}

// MARK: - Preview

struct StoriesRingView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            // No stories
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                StoriesRingView(hasStories: false, hasUnviewedStories: false, isCurrentUser: false, size: 80)
            }
            
            // Current user with stories
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                StoriesRingView(hasStories: true, hasUnviewedStories: true, isCurrentUser: true, size: 80)
            }
            
            // Other user with unviewed stories
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                StoriesRingView(hasStories: true, hasUnviewedStories: true, isCurrentUser: false, size: 80)
            }
            
            // Other user with viewed stories
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                StoriesRingView(hasStories: true, hasUnviewedStories: false, isCurrentUser: false, size: 80)
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
} 