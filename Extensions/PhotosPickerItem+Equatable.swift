import PhotosUI

@available(iOS 16.0, macOS 13.0, *)
extension PhotosPickerItem: Equatable {
    public static func == (lhs: PhotosPickerItem, rhs: PhotosPickerItem) -> Bool {
        lhs.itemIdentifier == rhs.itemIdentifier
    }
} 