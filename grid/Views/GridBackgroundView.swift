import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct GridBackgroundView: View {
    let backgroundColor: Color
    let backgroundImage: Image?

    var body: some View {
        if let img = backgroundImage {
            GeometryReader { geometry in
                img
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: max(geometry.size.width, UIScreen.main.bounds.width),
                        height: max(geometry.size.height, UIScreen.main.bounds.height)
                    )
                    .clipped()
                    .ignoresSafeArea(.all)
            }
            .ignoresSafeArea(.all)
        } else {
            backgroundColor
        }
    }
}
