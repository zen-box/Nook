import NookCore
import Observation
import SwiftUI
import UIKit

/// One native selection, input method and undo stack for the whole note.
struct NoteTextEditor: UIViewRepresentable {
    let runs: [NoteRun]
    let session: NoteEditorSession
    let attachments: AttachmentStore
    var onChange: ([NoteRun]) -> Void
    var onPhotoError: () -> Void

    func makeUIView(context: Context) -> NoteInputView {
        let view = NoteInputView(usingTextLayoutManager: false)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 15, bottom: 32, right: 15)
        view.textContainer.lineFragmentPadding = 5
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.adjustsFontForContentSizeCategory = true
        view.allowsEditingTextAttributes = true
        view.accessibilityIdentifier = "note.document"
        view.accessibilityLabel = String(localized: "Content")
        session.attach(view, attachments: attachments)
        session.onChange = onChange
        session.onPhotoError = onPhotoError
        session.setSource(runs)
        return view
    }

    func updateUIView(_ view: NoteInputView, context: Context) {
        session.onChange = onChange
        session.onPhotoError = onPhotoError
        if session.lastRuns != runs && view.markedTextRange == nil { session.setSource(runs) }
        session.refreshAttachmentAppearance()
    }
}

final class NoteInputView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?
    var onLayout: (() -> Void)?

    override func paste(_ sender: Any?) {
        if let image = UIPasteboard.general.image {
            onPasteImage?(image)
        } else if let string = UIPasteboard.general.string {
            // Text from other apps uses the current paragraph's style.
            insertText(string)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

@MainActor @Observable
final class NoteEditorSession: NSObject, UITextViewDelegate {
    var onAudioTap: ((FileRef) -> Void)?
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var isEditing = false
    private(set) var lastRuns: [NoteRun] = []
    private(set) var retainedFiles: [FileRef] = []
    @ObservationIgnored weak var textView: NoteInputView?
    @ObservationIgnored var onChange: (([NoteRun]) -> Void)?
    @ObservationIgnored var onPhotoError: (() -> Void)?
    @ObservationIgnored private var attachments: AttachmentStore?
    @ObservationIgnored private var lastWidth: CGFloat = 0
    @ObservationIgnored private var lastAppearance: UIUserInterfaceStyle?
    @ObservationIgnored private var photoSelection: NSRange?

    func attach(_ view: NoteInputView, attachments: AttachmentStore) {
        textView = view
        self.attachments = attachments
        view.delegate = self
        view.onPasteImage = { [weak self] image in
            guard let data = image.jpegData(compressionQuality: 0.9) else { self?.onPhotoError?(); return }
            self?.insertPhoto(data)
        }
        view.onLayout = { [weak self] in self?.resizeImages() }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedCheckbox(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    func setSource(_ runs: [NoteRun]) {
        guard let view = textView, let attachments else { return }
        let selection = view.selectedRange
        view.attributedText = NoteTextCodec.attributed(runs, attachments: attachments)
        view.selectedRange = NSRange(location: min(selection.location, view.textStorage.length), length: 0)
        view.typingAttributes = NoteTextCodec.attributes()
        lastRuns = runs
        for ref in runs.compactMap(\.attachment) { retain(ref) }
        lastWidth = 0
        resizeImages()
    }

    func beginEditing() { textView?.becomeFirstResponder() }
    func endEditing() { textView?.resignFirstResponder() }
    func undo() { textView?.undoManager?.undo(); publish() }
    func redo() { textView?.undoManager?.redo(); publish() }
    func rememberPhotoSelection() { photoSelection = textView?.selectedRange }

    func insertPlainText(_ text: String) {
        guard let view = textView else { return }
        replace(view.selectedRange, with: NSAttributedString(string: text + "\n", attributes: NoteTextCodec.attributes()))
    }
    func insertFile(_ ref: FileRef) {
        guard let view = textView, let attachments else { return }
        retain(ref)
        let saved = photoSelection ?? view.selectedRange; photoSelection = nil
        let range = NSRange(location: min(saved.location, view.textStorage.length), length: 0)
        replace(range, with: NoteTextCodec.attributed([NoteRun("\n"), NoteRun(attachment: ref), NoteRun("\n")], attachments: attachments))
    }

    func insertPhoto(_ data: Data, atSavedSelection: Bool = false) {
        guard let view = textView, let attachments else { return }
        view.unmarkText()
        do {
            let ref = try attachments.saveImage(data, name: "Photo.jpg")
            retain(ref)
            let selection = atSavedSelection ? (photoSelection ?? view.selectedRange) : view.selectedRange
            photoSelection = nil
            let range = NSRange(location: min(selection.location, view.textStorage.length),
                                length: min(selection.length, max(0, view.textStorage.length - selection.location)))
            let string = NSMutableAttributedString(string: "")
            if range.location > 0 && (view.text as NSString).substring(with: NSRange(location: range.location - 1, length: 1)) != "\n" {
                string.append(NSAttributedString(string: "\n", attributes: NoteTextCodec.attributes()))
            }
            string.append(NoteTextCodec.attributed([NoteRun(attachment: ref), NoteRun("\n")], attachments: attachments))
            replace(range, with: string)
            view.becomeFirstResponder()
        } catch { onPhotoError?() }
    }

    func toggleChecklist() {
        guard let view = textView else { return }
        view.unmarkText()
        view.becomeFirstResponder()
        let line = (view.text as NSString).paragraphRange(for: view.selectedRange)
        let index = line.location
        if index < view.textStorage.length, view.textStorage.attribute(NoteTextCodec.checkKey, at: index, effectiveRange: nil) != nil {
            replace(NSRange(location: index, length: 1), with: NSAttributedString(string: ""),
                    selection: NSRange(location: max(index, view.selectedRange.location - 1), length: 0))
        } else {
            let marker = NoteRun(checklist: ChecklistItem(text: ""))
            guard let attachments else { return }
            replace(NSRange(location: index, length: 0), with: NoteTextCodec.attributed([marker], attachments: attachments),
                    selection: NSRange(location: view.selectedRange.location + 1, length: 0))
        }
        view.typingAttributes = NoteTextCodec.attributes()
    }

    func setStyle(_ style: NoteRun.Style) {
        format(paragraph: true) { attributes in
            let old = attributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
            let traits = old.fontDescriptor.symbolicTraits
            return NoteTextCodec.attributes(style: style, bold: style == .heading, italic: traits.contains(.traitItalic))
        }
    }

    func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let view = textView else { return }
        let font = view.typingAttributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
        let enabled = !font.fontDescriptor.symbolicTraits.contains(trait)
        format { attributes in
            let font = attributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
            let old = font.fontDescriptor.symbolicTraits
            let style: NoteRun.Style = font.pointSize >= UIFont.preferredFont(forTextStyle: .title2).pointSize ? .heading : .body
            return NoteTextCodec.attributes(style: style, bold: trait == .traitBold ? enabled : old.contains(.traitBold),
                                             italic: trait == .traitItalic ? enabled : old.contains(.traitItalic))
        }
    }

    private func format(paragraph: Bool = false, _ transform: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]) {
        guard let view = textView else { return }
        view.unmarkText()
        view.becomeFirstResponder()
        let selection = view.selectedRange
        let range = paragraph ? (view.text as NSString).paragraphRange(for: selection) : selection
        guard range.length > 0 else {
            view.typingAttributes = transform(view.typingAttributes)
            return
        }
        let result = NSMutableAttributedString(attributedString: view.textStorage.attributedSubstring(from: range))
        let typingAttributes = view.typingAttributes
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { attributes, range, _ in
            guard attributes[.attachment] == nil else { return }
            result.addAttributes(transform(attributes), range: range)
        }
        replace(range, with: result, selection: selection)
        view.typingAttributes = transform(typingAttributes)
    }

    /// Register toolbar edits on the same undo stack as keyboard edits.
    private func replace(_ range: NSRange, with replacement: NSAttributedString, selection: NSRange? = nil) {
        guard let view = textView else { return }
        let original = view.textStorage.attributedSubstring(from: range)
        let oldSelection = view.selectedRange
        view.undoManager?.registerUndo(withTarget: self) { target in
            target.replace(NSRange(location: range.location, length: replacement.length), with: original, selection: oldSelection)
        }
        view.textStorage.replaceCharacters(in: range, with: replacement)
        view.selectedRange = selection ?? NSRange(location: range.location + replacement.length, length: 0)
        view.typingAttributes = NoteTextCodec.attributes()
        lastWidth = 0
        resizeImages()
        view.scrollRangeToVisible(view.selectedRange)
        publish()
    }

    func textViewDidChange(_ textView: UITextView) {
        guard textView.markedTextRange == nil else { return }
        publish()
    }

    func textViewDidBeginEditing(_ textView: UITextView) { isEditing = true }
    func textViewDidEndEditing(_ textView: UITextView) { isEditing = false; publish() }
    func textViewDidChangeSelection(_ textView: UITextView) {
        guard textView.markedTextRange == nil else { return }
        // Never carry an attachment's metadata into the next typed character.
        var attributes = textView.typingAttributes
        attributes.removeValue(forKey: .attachment)
        attributes.removeValue(forKey: NoteTextCodec.checkKey)
        attributes.removeValue(forKey: NoteTextCodec.fileKey)
        textView.typingAttributes = attributes
        updateUndoState()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard textView.markedTextRange == nil, text == "\n", range.length == 0, let attachments else { return true }
        let line = (textView.text as NSString).paragraphRange(for: range)
        guard line.location < textView.textStorage.length,
              textView.textStorage.attribute(NoteTextCodec.checkKey, at: line.location, effectiveRange: nil) != nil else { return true }
        let tail = (textView.text as NSString).substring(with: NSRange(location: line.location + 1, length: max(0, line.length - 1)))
        if tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            replace(NSRange(location: line.location, length: 1), with: NSAttributedString(string: ""),
                    selection: NSRange(location: line.location, length: 0))
        } else {
            replace(range, with: NoteTextCodec.attributed([NoteRun("\n"), NoteRun(checklist: ChecklistItem(text: ""))], attachments: attachments))
        }
        return false
    }

    @objc private func tappedCheckbox(_ gesture: UITapGestureRecognizer) {
        guard let view = textView, gesture.state == .ended else { return }
        var point = gesture.location(in: view)
        point.x -= view.textContainerInset.left
        point.y -= view.textContainerInset.top
        let manager = view.layoutManager
        let index = manager.characterIndex(for: point, in: view.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        if index < view.textStorage.length,
           let data = view.textStorage.attribute(NoteTextCodec.fileKey, at: index, effectiveRange: nil) as? Data,
           let ref = try? JSONDecoder().decode(FileRef.self, from: data), ref.kind == .audio {
            let glyph = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            if manager.boundingRect(forGlyphRange: glyph, in: view.textContainer).contains(point) { onAudioTap?(ref) }
            return
        }
        guard index < view.textStorage.length,
              let data = view.textStorage.attribute(NoteTextCodec.checkKey, at: index, effectiveRange: nil) as? Data,
              var item = try? JSONDecoder().decode(ChecklistItem.self, from: data), let attachments else { return }
        let glyph = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        guard manager.boundingRect(forGlyphRange: glyph, in: view.textContainer).insetBy(dx: -6, dy: -6).contains(point) else { return }
        item.isDone.toggle()
        replace(NSRange(location: index, length: 1), with: NoteTextCodec.attributed([NoteRun(checklist: item)], attachments: attachments), selection: view.selectedRange)
    }

    private func publish() {
        guard let view = textView else { return }
        guard importAttachments() else { return }
        let runs = NoteTextCodec.runs(view.textStorage)
        lastRuns = runs
        onChange?(runs)
        updateUndoState()
        // UIKit may register keyboard undo after its delegate callback has returned.
        Task { @MainActor [weak self] in self?.updateUndoState() }
    }

    /// Drag/drop and system text services can insert images without using paste().
    private func importAttachments() -> Bool {
        guard let view = textView, let attachments else { return true }
        var updates: [(NSRange, NSAttributedString.Key, Data)] = []
        var ids: Set<UUID> = []
        var failed = false
        view.textStorage.enumerateAttributes(in: NSRange(location: 0, length: view.textStorage.length)) { attributes, range, _ in
            if let data = attributes[NoteTextCodec.checkKey] as? Data,
               var item = try? JSONDecoder().decode(ChecklistItem.self, from: data) {
                if !ids.insert(item.id).inserted {
                    item.id = UUIDv7.make()
                    if let encoded = try? JSONEncoder().encode(item) { updates.append((range, NoteTextCodec.checkKey, encoded)) }
                }
            } else if attributes[NoteTextCodec.fileKey] == nil, let attachment = attributes[.attachment] as? NSTextAttachment {
                do {
                    guard let data = attachment.image?.jpegData(compressionQuality: 0.9)
                        ?? attachment.contents ?? attachment.fileWrapper?.regularFileContents else { throw AttachmentError.unreadableImage }
                    let ref = try attachments.saveImage(data, name: "Photo.jpg")
                    retain(ref)
                    updates.append((range, NoteTextCodec.fileKey, try JSONEncoder().encode(ref)))
                } catch { failed = true }
            }
        }
        // Apply metadata after enumeration so the traversal remains stable.
        for (range, key, data) in updates { view.textStorage.addAttribute(key, value: data, range: range) }
        if failed { onPhotoError?() }
        return !failed
    }

    private func updateUndoState() {
        canUndo = textView?.undoManager?.canUndo == true
        canRedo = textView?.undoManager?.canRedo == true
    }

    private func retain(_ ref: FileRef) {
        if !retainedFiles.contains(where: { $0.id == ref.id }) { retainedFiles.append(ref) }
    }

    func refreshAttachmentAppearance() {
        guard let view = textView, lastAppearance != view.traitCollection.userInterfaceStyle else { return }
        lastAppearance = view.traitCollection.userInterfaceStyle
        view.traitCollection.performAsCurrent {
            view.textStorage.enumerateAttributes(in: NSRange(location: 0, length: view.textStorage.length)) { attributes, _, _ in
                guard let data = attributes[NoteTextCodec.checkKey] as? Data,
                      let item = try? JSONDecoder().decode(ChecklistItem.self, from: data),
                      let attachment = attributes[.attachment] as? NSTextAttachment else { return }
                attachment.image = NoteTextCodec.checkboxImage(item.isDone)
            }
        }
        view.setNeedsDisplay()
    }

    private func resizeImages() {
        guard let view = textView else { return }
        let width = view.bounds.width - view.textContainerInset.left - view.textContainerInset.right - 10
        guard width > 0, abs(lastWidth - width) > 0.5 else { return }
        lastWidth = width
        view.textStorage.enumerateAttributes(in: NSRange(location: 0, length: view.textStorage.length)) { attributes, _, _ in
            guard attributes[NoteTextCodec.fileKey] != nil, let attachment = attributes[.attachment] as? NSTextAttachment,
                  let image = attachment.image, image.size.width > 0, image.size.height > 0 else { return }
            let scale = min(1, width / image.size.width, 480 / image.size.height)
            attachment.bounds = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
        }
        view.layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: view.textStorage.length), actualCharacterRange: nil)
    }
}

/// Metadata lives on the marker alone; ordinary text remains native attributed text.
@MainActor
enum NoteTextCodec {
    static let checkKey = NSAttributedString.Key("nook.checklist")
    static let fileKey = NSAttributedString.Key("nook.file")

    static func attributes(style: NoteRun.Style = .body, bold: Bool = false, italic: Bool = false) -> [NSAttributedString.Key: Any] {
        let base = UIFont.preferredFont(forTextStyle: style == .heading ? .title2 : .body)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold || style == .heading { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let font = UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor, size: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 8
        return [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
    }

    static func attributed(_ runs: [NoteRun], attachments: AttachmentStore) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for run in runs {
            if let item = run.checklist {
                let attachment = NSTextAttachment()
                attachment.image = checkboxImage(item.isDone)
                attachment.bounds = CGRect(x: 0, y: -4, width: 28, height: 23)
                let marker = NSMutableAttributedString(attachment: attachment)
                marker.addAttributes(attributes(), range: NSRange(location: 0, length: 1))
                marker.addAttribute(checkKey, value: try! JSONEncoder().encode(item), range: NSRange(location: 0, length: 1))
                result.append(marker)
            } else if let ref = run.attachment {
                let attachment = NSTextAttachment()
                attachment.image = (ref.kind == .audio ? audioImage(ref.name) : UIImage(contentsOfFile: attachments.imageURL(for: ref).path))
                    ?? UIImage(systemName: ref.kind == .image ? "photo.badge.exclamationmark" : "doc")
                let marker = NSMutableAttributedString(attachment: attachment)
                marker.addAttributes(attributes(), range: NSRange(location: 0, length: 1))
                marker.addAttribute(fileKey, value: try! JSONEncoder().encode(ref), range: NSRange(location: 0, length: 1))
                result.append(marker)
            } else {
                result.append(NSAttributedString(string: run.text, attributes: attributes(style: run.style, bold: run.bold, italic: run.italic)))
            }
        }
        return result
    }

    private static func audioImage(_ name: String) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 250, height: 50)).image { _ in
            UIColor.secondarySystemBackground.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 250, height: 50), cornerRadius: 10).fill()
            UIImage(systemName: "play.circle.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 12, y: 12, width: 26, height: 26))
            (name as NSString).draw(in: CGRect(x: 48, y: 16, width: 190, height: 22), withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.label])
        }
    }

    static func runs(_ string: NSAttributedString) -> [NoteRun] {
        var result: [NoteRun] = []
        var checklistIDs: Set<UUID> = []
        string.enumerateAttributes(in: NSRange(location: 0, length: string.length)) { attributes, range, _ in
            if let data = attributes[checkKey] as? Data, var item = try? JSONDecoder().decode(ChecklistItem.self, from: data) {
                if !checklistIDs.insert(item.id).inserted { item.id = UUIDv7.make() }
                item.text = ""
                result.append(NoteRun(checklist: item))
            } else if let data = attributes[fileKey] as? Data, let ref = try? JSONDecoder().decode(FileRef.self, from: data) {
                result.append(NoteRun(attachment: ref))
            } else {
                let font = attributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
                let traits = font.fontDescriptor.symbolicTraits
                result.append(NoteRun((string.string as NSString).substring(with: range),
                    style: font.pointSize >= UIFont.preferredFont(forTextStyle: .title2).pointSize ? .heading : .body,
                    bold: traits.contains(.traitBold), italic: traits.contains(.traitItalic)))
            }
        }
        return result
    }

    static func checkboxImage(_ done: Bool) -> UIImage? {
        let symbol = UIImage(systemName: done ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular))
        return symbol?.withTintColor(done ? UIColor(hex: 0x5BAF8B) : .secondaryLabel, renderingMode: .alwaysOriginal)
    }
}
