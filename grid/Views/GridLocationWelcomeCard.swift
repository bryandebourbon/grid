import SwiftUI

struct GridLocationWelcomeCard: View {
    var buttonTitle: String
    var onOpenProfile: () -> Void
    var onEnableLocation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocationOnboardingLogic.title)
                    .font(.title2.weight(.semibold))
                Text(LocationOnboardingLogic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Button(action: onOpenProfile) {
                    stepRow(number: 1, text: LocationOnboardingLogic.profileStep)
                }
                .buttonStyle(.plain)

                stepRow(number: 2, text: LocationOnboardingLogic.locationStep)
            }

            Button(action: onEnableLocation) {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(buttonTitle)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }
}
