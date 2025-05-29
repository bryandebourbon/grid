import Foundation
import NaturalLanguage
#if canImport(UIKit)
import UIKit
#endif

@MainActor
class ContentModerationService: ObservableObject {
    
    // MARK: - Text Content Filtering
    
    /// Checks if text content contains potentially objectionable material
    /// Uses NaturalLanguage framework for basic sentiment analysis
    func isTextAppropriate(_ text: String) -> (isAppropriate: Bool, reason: String?) {
        // Check for empty or very short content
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (false, "Empty content")
        }
        
        // Check length limits
        if text.count > 2000 {
            return (false, "Content too long")
        }
        
        // Use NaturalLanguage framework for sentiment analysis
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (sentiment, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        
        if let sentimentScore = sentiment?.rawValue, let score = Double(sentimentScore) {
            // Sentiment scores range from -1.0 (very negative) to 1.0 (very positive)
            // Flag extremely negative content as potentially inappropriate
            if score < -0.8 {
                return (false, "Content flagged for review")
            }
        }
        
        // Check for common inappropriate patterns
        let inappropriatePatterns = [
            // Spam patterns
            "(?i)click here",
            "(?i)free money",
            "(?i)make money fast",
            "(?i)visit my website",
            
            // Contact info sharing (discourage external contact)
            "(?i)whatsapp",
            "(?i)telegram",
            "(?i)instagram",
            "(?i)snapchat",
            
            // Excessive caps (shouting)
            "[A-Z]{10,}",
            
            // Repeated characters/symbols
            "([!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>\\?]){5,}",
            "(.)\\1{4,}" // Same character repeated 5+ times
        ]
        
        for pattern in inappropriatePatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return (false, "Content contains inappropriate patterns")
            }
        }
        
        return (true, nil)
    }
    
    // MARK: - Image Content Filtering
    
    /// Basic image validation (size, format, etc.)
    #if canImport(UIKit)
    func isImageAppropriate(_ imageData: Data) -> (isAppropriate: Bool, reason: String?) {
        // Check file size (limit to 10MB)
        let maxSize = 10 * 1024 * 1024 // 10MB
        if imageData.count > maxSize {
            return (false, "Image too large")
        }
        
        // Check if it's a valid image
        guard let image = UIImage(data: imageData) else {
            return (false, "Invalid image format")
        }
        
        // Check image dimensions (reasonable limits)
        let maxDimension: CGFloat = 4000
        if image.size.width > maxDimension || image.size.height > maxDimension {
            return (false, "Image dimensions too large")
        }
        
        // Check for extremely small images (might be tracking pixels)
        if image.size.width < 10 || image.size.height < 10 {
            return (false, "Image too small")
        }
        
        return (true, nil)
    }
    #endif
    
    // MARK: - Bio Content Filtering
    
    /// Specialized filtering for user bios
    func isBioAppropriate(_ bio: String) -> (isAppropriate: Bool, reason: String?) {
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check length
        if trimmedBio.count > 500 {
            return (false, "Bio too long")
        }
        
        // Check for contact information
        let contactPatterns = [
            // Email patterns
            "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
            // Phone number patterns
            "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b",
            "\\(\\d{3}\\)\\s?\\d{3}[-.]?\\d{4}",
            // Social media patterns
            "(?i)@[a-zA-Z0-9_]+",
            "(?i)follow me",
            "(?i)add me",
            "(?i)dm me"
        ]
        
        for pattern in contactPatterns {
            if trimmedBio.range(of: pattern, options: .regularExpression) != nil {
                return (false, "Bio contains contact information")
            }
        }
        
        // Use general text filtering
        return isTextAppropriate(trimmedBio)
    }
    
    // MARK: - Message Content Filtering
    
    /// Filtering for chat messages
    func isMessageAppropriate(_ message: String) -> (isAppropriate: Bool, reason: String?) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for empty messages
        if trimmedMessage.isEmpty {
            return (false, "Empty message")
        }
        
        // Check length
        if trimmedMessage.count > 1000 {
            return (false, "Message too long")
        }
        
        // Check for spam patterns
        let spamPatterns = [
            "(?i)buy now",
            "(?i)limited time",
            "(?i)act fast",
            "(?i)special offer",
            "(?i)discount",
            "(?i)promotion"
        ]
        
        for pattern in spamPatterns {
            if trimmedMessage.range(of: pattern, options: .regularExpression) != nil {
                return (false, "Message flagged as potential spam")
            }
        }
        
        return isTextAppropriate(trimmedMessage)
    }
    
    // MARK: - Auto-Moderation Actions
    
    /// Get suggested moderation action based on content type and violation
    func getSuggestedAction(for contentType: ContentType, violation: String) -> ModerationAction {
        switch contentType {
        case .message:
            if violation.contains("spam") {
                return .autoBlock
            } else {
                return .flagForReview
            }
        case .bio:
            return .requireEdit
        case .image:
            return .requireReplacement
        }
    }
}

// MARK: - Supporting Types

enum ContentType {
    case message
    case bio
    case image
}

enum ModerationAction {
    case allow
    case flagForReview
    case autoBlock
    case requireEdit
    case requireReplacement
    
    var description: String {
        switch self {
        case .allow:
            return "Content approved"
        case .flagForReview:
            return "Content flagged for manual review"
        case .autoBlock:
            return "Content automatically blocked"
        case .requireEdit:
            return "Content requires editing"
        case .requireReplacement:
            return "Content requires replacement"
        }
    }
} 