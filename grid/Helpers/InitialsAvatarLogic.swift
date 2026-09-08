import SwiftUI

/// Initials-on-color fallback when someone has no profile photo.
enum InitialsAvatarLogic {
    static let palette: [Color] = [
        Color(red: 0.20, green: 0.66, blue: 0.66),
        Color(red: 0.22, green: 0.45, blue: 0.91),
        Color(red: 0.49, green: 0.30, blue: 0.91),
        Color(red: 0.85, green: 0.28, blue: 0.45),
        Color(red: 0.95, green: 0.55, blue: 0.16),
        Color(red: 0.18, green: 0.60, blue: 0.38),
        Color(red: 0.15, green: 0.39, blue: 0.68),
        Color(red: 0.62, green: 0.22, blue: 0.54)
    ]

    static func initials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }
        if parts.count >= 2, let first = parts[0].first, let second = parts[1].first {
            return String([first, second]).uppercased()
        }
        let letters = trimmed.filter(\.isLetter)
        if letters.count >= 2 {
            return String(letters.prefix(2)).uppercased()
        }
        if let letter = letters.first {
            return String(letter).uppercased()
        }
        return "?"
    }

    static func paletteIndex(from seed: String) -> Int {
        let total = seed.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return abs(total) % palette.count
    }

    static func color(for seed: String) -> Color {
        palette[paletteIndex(from: seed)]
    }

    static func fontSize(forGridColumns columns: Int) -> CGFloat {
        switch columns {
        case ...2: return 56
        case 3: return 42
        default: return 28
        }
    }
}

struct InitialsAvatarFill: View {
    let name: String
    let seed: String
    var gridColumns: Int = 3

    var body: some View {
        ZStack {
            InitialsAvatarLogic.color(for: seed)
            Text(InitialsAvatarLogic.initials(from: name))
                .font(.system(size: InitialsAvatarLogic.fontSize(forGridColumns: gridColumns), weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
    }
}
