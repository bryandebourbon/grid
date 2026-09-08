import SwiftUI

struct AskDisplayNameView: View {
    let initialName: String
    let onSave: (String) -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    private var canContinue: Bool {
        ProfileDisplayNameLogic.isUsablePersonName(name)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("What’s your name?")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("This is how people see you in chat and notifications.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            TextField("Your name", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .multilineTextAlignment(.center)
                .font(.title2)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 32)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit {
                    submitIfValid()
                }

            Button("Continue") {
                submitIfValid()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue)

            Spacer()
        }
        .onAppear {
            if name.isEmpty {
                name = initialName
            }
            focused = true
        }
    }

    private func submitIfValid() {
        guard let trimmed = ProfileDisplayNameLogic.normalizedPersonName(name) else { return }
        onSave(trimmed)
    }
}
