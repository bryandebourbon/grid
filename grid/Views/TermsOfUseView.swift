import SwiftUI

/// Terms of Use / End User License Agreement.
///
/// Includes the zero-tolerance policy for objectionable content and abusive
/// users required for apps with user-generated content (App Store Review
/// Guideline 1.2).
struct TermsOfUseView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Terms of Use")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top)

                    Text("Last updated: \(Date().formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        section(
                            "Acceptance of Terms",
                            "By creating an account or using Grid, you agree to these Terms of Use. If you do not agree, do not use the app."
                        )

                        Divider()

                        section(
                            "Zero Tolerance for Objectionable Content",
                            "Grid has zero tolerance for objectionable content or abusive behavior. You agree not to post, send, or share content that is illegal, harassing, hateful, sexually exploitative, threatening, or otherwise objectionable, and not to harass or abuse other users.\n\nContent and accounts that violate this policy may be removed and terminated. We review reports of objectionable content and abusive users and act on them within 24 hours, which may include removing the content and ejecting the user who provided it."
                        )

                        Divider()

                        section(
                            "Reporting and Blocking",
                            "Every user can report objectionable content and block abusive users directly from a user's profile and from any chat. Reports are sent to our moderation team for review. You can manage blocked users at any time from Settings."
                        )

                        Divider()

                        section(
                            "Your Responsibilities",
                            "You are responsible for the content you share and for your interactions with other users. You must be at least 17 years old to use Grid. You agree to provide accurate profile information and to comply with all applicable laws."
                        )

                        Divider()

                        section(
                            "Account Termination",
                            "We may suspend or terminate accounts that violate these Terms, with or without notice. You may delete your account at any time from Settings, which removes your profile from the app."
                        )

                        Divider()

                        section(
                            "Contact",
                            "Questions about these Terms or to report a concern can be sent via the “Contact Us” option in Settings."
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Terms of Use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(body)
                .font(.body)
        }
    }
}

#Preview {
    TermsOfUseView()
}
