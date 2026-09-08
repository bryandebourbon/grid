import SwiftUI

/// Horizontal row of poster cards with a large Netflix-style rank number overlay.
struct NetflixRankedRow<Item: Identifiable, Poster: View>: View {
    let title: String
    let items: [Item]
    let poster: (Item, Int) -> Poster

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 16)

            if items.isEmpty {
                Text("Nothing nearby yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            NetflixRankedCard(rank: index + 1) {
                                poster(item, index + 1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.leading, 10)
                }
            }
        }
    }
}

struct NetflixRankedCard<Poster: View>: View {
    let rank: Int
    @ViewBuilder var poster: Poster

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            poster
                .frame(width: 112, height: 154)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .padding(.leading, 28)

            rankLabel
                .offset(x: -4, y: 10)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Number \(rank)")
    }

    private var rankLabel: some View {
        Text("\(rank)")
            .font(.system(size: 86, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Text("\(rank)")
                    .font(.system(size: 86, weight: .black, design: .rounded))
                    .foregroundStyle(.clear)
                    .shadow(color: .white.opacity(0.45), radius: 0, x: 0, y: -0.8)
                    .shadow(color: .black.opacity(0.55), radius: 0, x: 1.2, y: 1.8)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

struct InterestRankPoster: View {
    let interest: Interest
    let peopleCount: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    InterestMapsChrome.circleColor(for: interest),
                    InterestMapsChrome.circleColor(for: interest).opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(interest.emoji)
                    .font(.system(size: 34))
                Text(interest.rawValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if peopleCount > 0 {
                    Text(peopleCount == 1 ? "1 person" : "\(peopleCount) people")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(10)
        }
    }
}

struct VenueRankPoster: View {
    let venue: InterestVenue

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    InterestMapsChrome.circleColor(for: venue.interest).opacity(0.95),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.interest.emoji)
                    .font(.system(size: 28))
                Text(venue.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(venue.distanceLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(10)
        }
    }
}
