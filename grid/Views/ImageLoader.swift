import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: Image?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentAsset: CKAsset?
    private var imageLoadingTask: Task<Void, Never>?

    func loadImage(from asset: CKAsset?) {
        guard let asset = asset else {
            image = nil
            currentAsset = nil
            return
        }
        guard asset.fileURL?.absoluteString != currentAsset?.fileURL?.absoluteString || image == nil else { return }

        isLoading = true
        currentAsset = asset
        errorMessage = nil
        imageLoadingTask?.cancel()

        imageLoadingTask = Task {
            do {
                guard let fileURL = asset.fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
                    throw NSError(domain: "ImageLoader", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "CKAsset file is not available locally."
                    ])
                }

                let data = try Data(contentsOf: fileURL)
                #if canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw NSError(domain: "ImageLoader", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not create UIImage from asset data."
                    ])
                }
                await MainActor.run {
                    self.image = Image(uiImage: uiImage)
                    self.isLoading = false
                }
                #else
                guard let nsImage = NSImage(data: data) else {
                    throw NSError(domain: "ImageLoader", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not create image from asset data."
                    ])
                }
                await MainActor.run {
                    self.image = Image(nsImage: nsImage)
                    self.isLoading = false
                }
                #endif
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not load image."
                    self.image = nil
                    self.isLoading = false
                }
            }
        }
    }

    func cancel() {
        imageLoadingTask?.cancel()
        isLoading = false
    }
}
