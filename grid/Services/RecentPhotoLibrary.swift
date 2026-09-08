import Foundation
import Photos
#if canImport(UIKit)
import UIKit
#endif

/// Pages through the user's most recent photos for the in-chat strip.
@MainActor
final class RecentPhotoLibrary: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var authorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true

    private var fetchResult: PHFetchResult<PHAsset>?
    private var nextIndex = 0
    private let pageSize = 24
    private var didPrepare = false

    func prepare() async {
        if !didPrepare {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            didPrepare = true
        }
        guard authorization == .authorized || authorization == .limited else {
            assets = []
            hasMore = false
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        nextIndex = 0
        assets = []
        hasMore = (fetchResult?.count ?? 0) > 0
        loadNextPage()
    }

    func loadNextPage() {
        guard !isLoading, hasMore, let fetchResult else { return }
        isLoading = true
        let end = min(nextIndex + pageSize, fetchResult.count)
        guard end > nextIndex else {
            hasMore = false
            isLoading = false
            return
        }

        var page: [PHAsset] = []
        page.reserveCapacity(end - nextIndex)
        fetchResult.enumerateObjects(at: IndexSet(integersIn: nextIndex..<end), options: []) { asset, _, _ in
            page.append(asset)
        }
        assets.append(contentsOf: page)
        nextIndex = end
        hasMore = nextIndex < fetchResult.count
        isLoading = false
    }

    static func jpegData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            var resumed = false
            let finish: (Data?) -> Void = { data in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: data)
            }

            let target = CGSize(width: 1600, height: 1600)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                #if canImport(UIKit)
                finish(image?.jpegData(compressionQuality: 0.82))
                #else
                finish(nil)
                #endif
            }
        }
    }
}
