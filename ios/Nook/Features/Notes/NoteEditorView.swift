import PhotosUI
import SwiftUI
import NookCore

/// Edits a note in place. Changes are saved as you type; a note left empty is dropped.
struct NoteEditorView: View {
    let noteID: UUID
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Note?
    @State private var confirmDelete = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var isVisible = false
    @FocusState private var focus: EditorFocus?

    enum EditorFocus: Hashable {
        case title
        case body
        case item(UUID)
    }

    var body: some View {
        Group {
            if let note = Binding($draft) {
                editor(note)
            } else {
                ContentUnavailableView("Note not found", systemImage: "note.text")
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
            }
        }
        .onAppear {
            isVisible = true
            if draft == nil {
                draft = store.note(id: noteID)
                if draft?.isBlank == true {
                    focus = .title
                }
            }
        }
        .onChange(of: draft) { _, newValue in
            if let newValue {
                store.saveNote(newValue)
            }
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            addPhoto(item)
        }
        .onDisappear {
            isVisible = false
            if store.note(id: noteID) != nil, let draft { store.saveNote(draft) }
            store.discardIfBlank(noteID)
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                if store.deleteNote(noteID) { dismiss() }
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if draft?.isPinned == true {
                Button {
                    draft?.isPinned = false
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
            } else {
                Button {
                    draft?.isPinned = true
                } label: {
                    Label("Pin", systemImage: "pin")
                }
            }
            Divider()
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("More"))
    }

    private func editor(_ note: Binding<Note>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    categoryMenu(note)
                    if note.wrappedValue.isPinned {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Pastel.blue.strong)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Pastel.blue.soft, in: Capsule())
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: note.title)
                        .font(.system(.title, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focus = .body }
                    Text("Edited \(note.wrappedValue.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(NookFont.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                checklistSection(note)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Content")
                        .font(NookFont.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    TextField("Write something…", text: note.body, axis: .vertical)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(6...)
                        .focused($focus, equals: .body)
                        .card(padding: 14)
                }
                photosSection(note)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func categoryMenu(_ note: Binding<Note>) -> some View {
        let category = note.wrappedValue.category
        return Menu {
            ForEach(NoteCategory.allCases, id: \.self) { option in
                Button {
                    note.wrappedValue.category = option
                } label: {
                    Label(option.label, systemImage: option.symbol)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.symbol)
                Text(category.label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(category.pastel.strong)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(category.pastel.soft, in: Capsule())
        }
        .accessibilityLabel(Text("Category"))
    }

    private func checklistSection(_ note: Binding<Note>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Checklist")
                    .font(NookFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !note.wrappedValue.checklist.isEmpty {
                    Text(verbatim: "\(note.wrappedValue.completedChecklistCount)/\(note.wrappedValue.checklist.count)")
                        .font(.system(.footnote, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(note.checklist) { $item in
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.snappy) {
                                item.isDone.toggle()
                            }
                        } label: {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(item.isDone ? Pastel.mint.strong : Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.isDone ? Text("Mark as not done") : Text("Mark as done"))
                        TextField("To-do", text: $item.text)
                            .font(.subheadline)
                            .strikethrough(item.isDone, color: Theme.textTertiary)
                            .foregroundStyle(item.isDone ? Theme.textSecondary : Theme.textPrimary)
                            .focused($focus, equals: .item(item.id))
                            .submitLabel(.next)
                            .onSubmit {
                                submit(item, in: note)
                            }
                        Button {
                            remove(item.id, from: note)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove item"))
                    }
                    .padding(.vertical, 6)
                }
                Button {
                    addItem(after: nil, to: note)
                } label: {
                    Label("Add item", systemImage: "plus")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .card(padding: 14)
        }
    }

    private func photosSection(_ note: Binding<Note>) -> some View {
        let photos = note.wrappedValue.attachments.filter { $0.kind == .image }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photos")
                    .font(NookFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isLoadingPhoto {
                    ProgressView()
                }
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Label("Add Photo", systemImage: "photo.badge.plus")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .disabled(isLoadingPhoto)
            }
            if !photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(photos) { photo in
                        AttachmentImage(ref: photo, thumbnail: false, cornerRadius: 14)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    removePhoto(photo, from: note)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color.black.opacity(0.45))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .accessibilityLabel(Text("Remove photo"))
                            }
                    }
                }
            }
        }
    }

    private func addPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer {
                isLoadingPhoto = false
                photoSelection = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                router.showToast(ToastMessage(text: "Couldn't add the photo", symbol: "exclamationmark.triangle.fill", isWarning: true))
                return
            }
            guard isVisible, store.note(id: noteID) != nil, var updated = draft else { return }
            do {
                let ref = try store.storePhoto(data)
                updated.attachments.append(ref)
                if store.saveNote(updated) {
                    draft = updated
                } else {
                    store.discardPhoto(ref)
                }
            } catch {
                router.showToast(ToastMessage(text: "Couldn't add the photo", symbol: "exclamationmark.triangle.fill", isWarning: true))
            }
        }
    }

    private func removePhoto(_ ref: FileRef, from note: Binding<Note>) {
        note.wrappedValue.attachments.removeAll { $0.id == ref.id }
    }

    /// Return on a filled item adds the next one; on an empty item it removes it.
    private func submit(_ item: ChecklistItem, in note: Binding<Note>) {
        if item.text.trimmingCharacters(in: .whitespaces).isEmpty {
            remove(item.id, from: note)
        } else {
            addItem(after: item.id, to: note)
        }
    }

    private func addItem(after id: UUID?, to note: Binding<Note>) {
        let newItem = ChecklistItem(text: "")
        if let id, let index = note.wrappedValue.checklist.firstIndex(where: { $0.id == id }) {
            note.wrappedValue.checklist.insert(newItem, at: index + 1)
        } else {
            note.wrappedValue.checklist.append(newItem)
        }
        focus = .item(newItem.id)
    }

    private func remove(_ id: UUID, from note: Binding<Note>) {
        note.wrappedValue.checklist.removeAll { $0.id == id }
    }
}
