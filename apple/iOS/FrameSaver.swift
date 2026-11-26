import UIKit
import Photos

/// Saves a rain frame to the photo library. Asks for add-only access: the app never reads the library.
enum FrameSaver {
    enum Outcome {
        case saved
        case denied
        case failed
    }

    /// `completion` is always called on the main thread.
    static func save(_ image: UIImage, completion: @escaping (Outcome) -> Void) {
        let finish: (Outcome) -> Void = { outcome in
            DispatchQueue.main.async { completion(outcome) }
        }
        // PNG keeps the thin glyph edges exact.
        guard let png = image.pngData() else {
            finish(.failed)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                finish(.denied)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
            }, completionHandler: { success, _ in
                finish(success ? .saved : .failed)
            })
        }
    }
}
