import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: Image?
    @Published var imageSize: CGSize?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentAsset: CKAsset?
    private var currentFingerprint: String?
    private var imageLoadingTask: Task<Void, Never>?

    func loadImage(from asset: CKAsset?, force: Bool = false) {
        guard let asset = asset else {
            image = nil
            imageSize = nil
            currentAsset = nil
            currentFingerprint = nil
            return
        }
        let fingerprint = ProfileImageRefreshLogic.loadKey(for: asset)
        guard force || fingerprint != currentFingerprint || image == nil else { return }

        isLoading = true
        currentAsset = asset
        currentFingerprint = fingerprint
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
                    self.imageSize = uiImage.size
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
                    self.imageSize = nsImage.size
                    self.isLoading = false
                }
                #endif
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not load image."
                    self.image = nil
                    self.imageSize = nil
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
