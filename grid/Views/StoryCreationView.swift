import SwiftUI
import PhotosUI
import UIKit

struct StoryCreationView: View {
    @ObservedObject var viewModel: GridViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedImageData: Data?
    @State private var selectedImage: UIImage?
    @State private var caption: String = ""
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var photosPickerItem: PhotosPickerItem?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let selectedImage = selectedImage {
                    // Story preview and editing
                    VStack(spacing: 16) {
                        // Image preview (circular like stories)
                        ZStack {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 300, height: 300)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 3)
                                        .shadow(radius: 5)
                                )
                        }
                        
                        // Caption input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add a caption (optional)")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            TextField("What's on your mind?", text: $caption, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding(.horizontal)
                        
                        // Post button
                        Button(action: postStory) {
                            HStack {
                                if isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isUploading ? "Posting..." : "Share Story")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .disabled(isUploading || selectedImageData == nil)
                        .padding(.horizontal)
                        
                        // Error message
                        if let uploadError = uploadError {
                            Text(uploadError)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                } else {
                    // Photo selection options
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            Text("Create Your Story")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Share a moment that will disappear in 24 hours")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Photo source options
                        VStack(spacing: 12) {
                            // Camera button
                            Button(action: {
                                showingCamera = true
                            }) {
                                HStack {
                                    Image(systemName: "camera.fill")
                                        .font(.title2)
                                    Text("Take Photo")
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .foregroundColor(.primary)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            
                            // Photo library button
                            PhotosPicker(selection: $photosPickerItem, matching: .images) {
                                HStack {
                                    Image(systemName: "photo.fill")
                                        .font(.title2)
                                    Text("Choose Photo")
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .foregroundColor(.primary)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                }
            }
            .padding(.top)
            .navigationTitle("New Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if selectedImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Change Photo") {
                            selectedImage = nil
                            selectedImageData = nil
                            caption = ""
                            uploadError = nil
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView { imageData in
                handleSelectedImageData(imageData)
            }
        }
        .onChange(of: photosPickerItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        handleSelectedImageData(data)
                    }
                }
            }
        }
    }
    
    private func handleSelectedImageData(_ data: Data) {
        selectedImageData = data
        selectedImage = UIImage(data: data)
        uploadError = nil
    }
    
    private func postStory() {
        guard let imageData = selectedImageData else { return }
        
        isUploading = true
        uploadError = nil
        
        Task {
            do {
                guard let profile = viewModel.currentUserProfile else { return }
                try await viewModel.storiesService.uploadStoryAndRefresh(
                    imageData: imageData,
                    caption: caption.isEmpty ? nil : caption,
                    userID: profile.userID,
                    deviceID: profile.deviceID
                )
                
                await MainActor.run {
                    // Success - dismiss
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadError = "Failed to post story: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (Data) -> Void
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                parent.onImageCaptured(imageData)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Preview

struct StoryCreationView_Previews: PreviewProvider {
    static var previews: some View {
        StoryCreationView(viewModel: GridViewModel())
    }
} 