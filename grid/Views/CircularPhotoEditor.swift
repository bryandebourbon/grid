import SwiftUI
import PhotosUI

struct CircularPhotoEditor: View {
    @Binding var selectedPhotoData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var image: UIImage?
    
    // Pan and zoom state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    // UI state
    @State private var showPhotoPicker = false
    
    let circleSize: CGFloat
    let placeholder: String
    let onPhotoChanged: ((Data) -> Void)?
    
    init(
        selectedPhotoData: Binding<Data?>,
        circleSize: CGFloat = 200,
        placeholder: String = "Add Photo",
        onPhotoChanged: ((Data) -> Void)? = nil
    ) {
        self._selectedPhotoData = selectedPhotoData
        self.circleSize = circleSize
        self.placeholder = placeholder
        self.onPhotoChanged = onPhotoChanged
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Circular photo editor area
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: circleSize, height: circleSize)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                    )
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: circleSize, height: circleSize)
                        .clipShape(Circle())
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastScale * value
                                        // Limit scale between 0.5x and 3x
                                        scale = max(0.5, min(3.0, newScale))
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        let newOffset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                        
                                        // Limit pan to keep image reasonably within bounds
                                        let maxOffset = circleSize * 0.3
                                        offset = CGSize(
                                            width: max(-maxOffset, min(maxOffset, newOffset.width)),
                                            height: max(-maxOffset, min(maxOffset, newOffset.height))
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: circleSize * 0.3))
                            .foregroundColor(.secondary)
                        
                        Text(placeholder)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Action buttons
            VStack(spacing: 12) {
                Button(action: { showPhotoPicker = true }) {
                    HStack {
                        Image(systemName: image == nil ? "photo" : "photo.badge.plus")
                        Text(image == nil ? "Select Photo" : "Change Photo")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                if image != nil {
                    HStack(spacing: 20) {
                        Button("Reset Position") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        
                        Button("Save Changes") {
                            saveEditedPhoto()
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    }
                }
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                if let item = newItem,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    
                    await MainActor.run {
                        image = uiImage
                        // Reset transform when new image is loaded
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .onAppear {
            if let data = selectedPhotoData,
               let uiImage = UIImage(data: data) {
                image = uiImage
            }
        }
    }
    
    private func saveEditedPhoto() {
        guard let image = image else { return }
        
        let renderer = ImageRenderer(content: 
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: circleSize, height: circleSize)
                .clipShape(Circle())
        )
        
        renderer.scale = UIScreen.main.scale
        
        if let renderedImage = renderer.uiImage,
           let data = renderedImage.jpegData(compressionQuality: 0.8) {
            selectedPhotoData = data
            onPhotoChanged?(data)
        }
    }
}

#Preview {
    CircularPhotoEditor(
        selectedPhotoData: .constant(nil),
        circleSize: 200,
        placeholder: "Add Profile Photo"
    )
    .padding()
} 