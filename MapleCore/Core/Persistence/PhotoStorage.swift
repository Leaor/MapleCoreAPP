import UIKit
import ImageIO

/// Proof-of-work photos are saved to the app container first, then queued for upload.
/// The camera never blocks on the network.
enum PhotoStorage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MapleCore/Photos", isDirectory: true)
    }

    /// Writes JPEG data and returns the file name to store on `VisitPhoto.localFileName`.
    static func save(_ image: UIImage, quality: CGFloat = 0.8) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }

    static func save(data: Data) throws -> String {
        guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        return try save(image)
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}

/// Small in-memory thumbnail cache so grids scroll smoothly.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for fileName: String, maxPixel: CGFloat = 600) async -> UIImage? {
        let key = "\(fileName)-\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let url = PhotoStorage.url(for: fileName)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
