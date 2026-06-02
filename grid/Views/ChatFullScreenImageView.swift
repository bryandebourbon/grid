import SwiftUI
import PhotosUI

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
            // Black background
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    // Only dismiss if not zoomed in
                    if scale <= 1.0 {
                        onDismiss()
                    }
                }
            
            VStack {
                // Header with encryption indicator and close button
                HStack {
                    // Encryption indicator
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
                    
                    // Close button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
                .padding()
                .opacity(scale > 1.0 ? 0.3 : 1.0) // Fade header when zoomed
                .animation(.easeInOut(duration: 0.2), value: scale)
                
                Spacer()
                
                // Zoomable image
                imageData.image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .onTapGesture(count: 2) {
                        // Double tap to zoom in/out
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            if scale > 1.0 {
                                // Reset zoom
                                scale = 1.0
                                offset = .zero
                            } else {
                                // Zoom in to 2x
                                scale = 2.0
                            }
                        }
                    }
                    .onTapGesture {
                        // Single tap - only dismiss if not zoomed
                        if scale <= 1.0 {
                            onDismiss()
                        }
                    }
                    .gesture(
                        SimultaneousGesture(
                            // Magnification gesture for pinch-to-zoom
                            MagnificationGesture()
                                .onChanged { value in
                                    let newScale = lastScale * value
                                    scale = max(1.0, min(newScale, 5.0)) // Limit zoom between 1x and 5x
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    
                                    // Reset position when zoomed out to 1.0 or close to it
                                    if scale <= 1.1 {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                            scale = 1.0
                                            offset = .zero
                                        }
                                        lastScale = 1.0
                                        lastOffset = .zero
                                    }
                                },
                            
                            // Drag gesture for panning when zoomed
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        let newOffset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                        offset = limitOffset(newOffset)
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
    
    // Helper function to limit panning within reasonable bounds
    private func limitOffset(_ newOffset: CGSize) -> CGSize {
        let maxOffset: CGFloat = 200 * scale // Adjust this value as needed
        
        let limitedWidth = max(-maxOffset, min(maxOffset, newOffset.width))
        let limitedHeight = max(-maxOffset, min(maxOffset, newOffset.height))
        
        return CGSize(width: limitedWidth, height: limitedHeight)
    }
}
