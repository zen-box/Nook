import Foundation
import ImageIO
import UIKit
import NookCore

enum AttachmentError: Error {
    case unreadableImage
}

/// Photos attached to notes, stored as JPEG files next to the database. Each photo is kept at
/// up to 2048 pixels plus a small thumbnail for lists; re-encoding also drops location data.
struct AttachmentStore: Sendable {
    let folder: URL

    static func makeDefault() throws -> AttachmentStore {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Attachments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return AttachmentStore(folder: folder)
    }

    /// A throwaway folder, for tests and UI tests.
    static func makeTemporary() -> AttachmentStore {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Attachments-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return AttachmentStore(folder: folder)
    }

    func imageURL(for ref: FileRef) -> URL {
        folder.appending(path: "\(ref.id.uuidString.lowercased()).jpg")
    }

    func thumbnailURL(for ref: FileRef) -> URL {
        folder.appending(path: "\(ref.id.uuidString.lowercased())-thumb.jpg")
    }

    func fileURL(for ref: FileRef) -> URL {
        ref.kind == .image ? imageURL(for: ref) : folder.appending(path: "\(ref.id.uuidString.lowercased()).\(ref.kind == .audio ? "m4a" : "bin")")
    }

    func saveAudio(_ source: URL) throws -> FileRef {
        let data = try Data(contentsOf: source)
        guard !data.isEmpty, data.count <= 90 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let ref = FileRef(name: "Recording.m4a", kind: .audio, byteCount: Int64(data.count))
        try data.write(to: fileURL(for: ref), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return ref
    }

    func saveImage(_ data: Data, name: String) throws -> FileRef {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = Self.jpeg(from: source, maxPixelSize: 2048, quality: 0.85),
              let thumbnail = Self.jpeg(from: source, maxPixelSize: 360, quality: 0.8)
        else {
            throw AttachmentError.unreadableImage
        }
        let ref = FileRef(name: name, kind: .image, byteCount: Int64(full.count))
        do {
            try full.write(to: imageURL(for: ref), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try thumbnail.write(to: thumbnailURL(for: ref), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            delete(ref)
            throw error
        }
        return ref
    }

    func delete(_ ref: FileRef) {
        // Immutable sync history can still reference removed attachments.
        if FileManager.default.fileExists(atPath: folder.appending(path: ".retain-sync-history").path) { return }
        try? FileManager.default.removeItem(at: fileURL(for: ref))
        try? FileManager.default.removeItem(at: imageURL(for: ref))
        try? FileManager.default.removeItem(at: thumbnailURL(for: ref))
    }

    private static func jpeg(from source: CGImageSource, maxPixelSize: Int, quality: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: quality)
    }
}
