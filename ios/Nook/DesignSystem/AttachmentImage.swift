import SwiftUI
import UIKit
import UniformTypeIdentifiers
import NookCore

/// A photo attached to a note, read from disk. Shows a soft placeholder while it loads or when
/// the file is missing (backups do not contain photos).
struct AttachmentImage: View {
    let ref: FileRef
    /// Use the small copy made for lists.
    var thumbnail = true
    var cornerRadius: CGFloat = 16
    @Environment(AppStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        Theme.primarySoft
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Theme.primary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: ref.id) {
                let url = thumbnail ? store.attachments.thumbnailURL(for: ref) : store.attachments.imageURL(for: ref)
                image = UIImage(contentsOfFile: url.path(percentEncoded: false))
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Photo"))
    }
}

@MainActor
enum Clipboard {
    static func copy(_ value: String) {
        UIPasteboard.general.string = value
    }

    /// Passwords and card numbers stay on this device's clipboard for 90 seconds only.
    static func copySecret(_ value: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: value]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(90)]
        )
    }
}
