import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Full-screen image viewer
struct FullScreenImageView: View {
    let imageData: FullScreenImageData
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    if scale <= 1.0 {
                        onDismiss()
                    }
                }

            VStack {
                HStack {
                    if imageData.isEncrypted {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("Encrypted")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding()
                .opacity(scale > 1.0 ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: scale)

                Spacer()

                imageData.image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            if scale > 1.0 {
                                scale = 1.0
                                offset = .zero
                            } else {
                                scale = 2.0
                            }
                        }
                    }
                    .onTapGesture {
                        if scale <= 1.0 {
                            onDismiss()
                        }
                    }
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, min(lastScale * value, 5.0))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale <= 1.1 {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                            scale = 1.0
                                            offset = .zero
                                        }
                                        lastScale = 1.0
                                        lastOffset = .zero
                                    }
                                },
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        offset = limitOffset(CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        ))
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )

                Spacer()
            }
        }
    }

    private func limitOffset(_ newOffset: CGSize) -> CGSize {
        let maxOffset: CGFloat = 200 * scale
        return CGSize(
            width: max(-maxOffset, min(maxOffset, newOffset.width)),
            height: max(-maxOffset, min(maxOffset, newOffset.height))
        )
    }
}

#if canImport(UIKit)
/// Close control lives in its own overlay so photo gestures cannot eat the tap.
struct PhotoCloseButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> PhotoCloseHost {
        let host = PhotoCloseHost()
        host.button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return host
    }

    func updateUIView(_ host: PhotoCloseHost, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}

final class PhotoCloseHost: UIView {
    let button = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        button.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 28
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 56, height: 56)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -12, dy: -12).contains(point)
    }
}
#endif
