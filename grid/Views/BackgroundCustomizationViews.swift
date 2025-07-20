import SwiftUI
import PhotosUI

// MARK: - Color Picker Sheet

struct BackgroundColorPickerView: View {
    @Binding var selectedColor: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack {
                ColorPicker("Select Background Color", selection: $selectedColor, supportsOpacity: true)
                    .padding()
                Spacer()
            }
            .navigationTitle("Background Color")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Photo Picker Sheet

struct BackgroundPhotoPickerView: View {
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var backgroundImage: Image?
    @Environment(\.dismiss) private var dismiss
    @State private var loading: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let img = backgroundImage {
                    img
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 300)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 200, height: 200)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        )
                }

                PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                    Text("Choose Photo")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(loading)

                Spacer()
            }
            .padding()
            .navigationTitle("Background Photo")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if backgroundImage != nil {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .onChange(of: selectedItem) { newItem in
                guard let newItem = newItem else { return }
                loading = true
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        #if canImport(UIKit)
                        if let uiImage = UIImage(data: data) {
                            await MainActor.run {
                                backgroundImage = Image(uiImage: uiImage)
                            }
                        }
                        #else
                        if let nsImage = NSImage(data: data) {
                            await MainActor.run {
                                backgroundImage = Image(nsImage: nsImage)
                            }
                        }
                        #endif
                    }
                    loading = false
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// Note: gridBackgroundView is implemented inside GridView struct directly 