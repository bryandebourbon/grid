import SwiftUI

/// Instagram Notes-style status bubble that sits on a profile photo.
struct BioStatusBubble: View {
    let text: String
    var isPlaceholder = false
    var fontSize: CGFloat = BioStatusBubbleLogic.baseFontSize

    private let fill = Color.white.opacity(0.92)
    private let textGray = Color(white: 0.42)
    private var scale: CGFloat { fontSize / BioStatusBubbleLogic.baseFontSize }

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(isPlaceholder ? textGray.opacity(0.72) : textGray)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 11 * scale)
                .padding(.vertical, 8 * scale)
                .frame(maxWidth: 124 * scale)
                .background {
                    Capsule(style: .continuous)
                        .fill(fill)
                }

            SpeechBubbleTail()
                .fill(fill)
                .frame(width: 20 * scale, height: 11 * scale)
                .offset(y: -1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
