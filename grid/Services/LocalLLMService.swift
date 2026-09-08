import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Talks to Apple's on-device Foundation model. Never leaves the phone.
@MainActor
final class LocalLLMService {
    static let shared = LocalLLMService()

    private var sessionStorage: Any?

    private static let unavailableFallback =
        "This build can’t reach an on-device model. Update iOS and turn on Apple Intelligence to chat here."

    func reply(
        to userText: String,
        priorMessages: [Message],
        currentDeviceID: String
    ) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await respondOnDevice(
                to: userText,
                priorMessages: priorMessages,
                currentDeviceID: currentDeviceID
            )
        }
        #endif
        return Self.unavailableFallback
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func respondOnDevice(
        to userText: String,
        priorMessages: [Message],
        currentDeviceID: String
    ) async -> String {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            return "This phone doesn’t support Apple Intelligence, so I can’t reply on-device."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to chat with me on this phone."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again in a minute."
        case .unavailable:
            return "The on-device model isn’t available right now."
        }

        let session: LanguageModelSession
        if let existing = sessionStorage as? LanguageModelSession {
            session = existing
        } else {
            session = LanguageModelSession(
                instructions: instructions(including: priorMessages, currentDeviceID: currentDeviceID)
            )
            sessionStorage = session
        }

        do {
            let response = try await session.respond(to: userText)
            return response.content
        } catch {
            return "I couldn’t reply: \(error.localizedDescription)"
        }
    }

    @available(iOS 26.0, *)
    private func instructions(including priorMessages: [Message], currentDeviceID: String) -> String {
        var lines = [
            "You are Local LLM, a square on the user's Grid social app.",
            "You live only on this phone. You cannot see other users, photos, or the network.",
            "Keep replies short and conversational."
        ]
        let recent = priorMessages.suffix(16)
        if !recent.isEmpty {
            lines.append("Recent conversation:")
            for message in recent {
                let role = message.senderDeviceID == currentDeviceID ? "User" : "You"
                lines.append("\(role): \(message.text)")
            }
        }
        return lines.joined(separator: "\n")
    }
    #endif
}
