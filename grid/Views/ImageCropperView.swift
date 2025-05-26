import SwiftUI
#if canImport(UIKit)

struct ImageCropperView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    // State for gestures
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let cropSize = min(geo.size.width, geo.size.height)
            VStack {
                ZStack {
                    Color.black.opacity(0.8).ignoresSafeArea()
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cropSize, height: cropSize)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = value.translation
                                    },
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = value
                                    }
                            )
                        )
                        .clipped()
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                .frame(width: cropSize, height: cropSize)

                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    Spacer()
                    Button("Use Photo") {
                        let cropped = cropImage(original: image, cropSize: cropSize, scale: scale, offset: offset)
                        onCrop(cropped)
                        dismiss()
                    }
                }
                .padding()
            }
        }
    }

    private func cropImage(original: UIImage, cropSize: CGFloat, scale: CGFloat, offset: CGSize) -> UIImage {
        let imageSize = original.size
        // Scale to fill crop area initially
        let baseScale = max(cropSize / imageSize.width, cropSize / imageSize.height)
        let totalScale = baseScale * scale
        let scaledSize = CGSize(width: imageSize.width * totalScale, height: imageSize.height * totalScale)
        let x = (scaledSize.width - cropSize) / 2 - offset.width
        let y = (scaledSize.height - cropSize) / 2 - offset.height
        let cropRect = CGRect(x: x / totalScale, y: y / totalScale, width: cropSize / totalScale, height: cropSize / totalScale)
        guard let cgImage = original.cgImage?.cropping(to: cropRect) else { return original }
        return UIImage(cgImage: cgImage)
    }
}

#endif
