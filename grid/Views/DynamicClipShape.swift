import SwiftUI

struct DynamicClipShape: ViewModifier {
    let useCircular: Bool

    func body(content: Content) -> some View {
        if useCircular {
            content.clipShape(Circle())
        } else {
            content.clipShape(Rectangle())
        }
    }
}
