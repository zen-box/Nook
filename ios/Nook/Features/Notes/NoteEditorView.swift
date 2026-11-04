import PhotosUI
import SwiftUI
import NookCore

/// A continuous document: text, checklists and photos share the cursor and undo history.
struct NoteEditorView: View {
    let noteID: UUID
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Note?
    @State private var session = NoteEditorSession()
    @State private var confirmDelete = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var isVisible = false
    @FocusState private var titleFocused: Bool

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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!session.canUndo).accessibilityLabel(Text("Undo"))
                Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!session.canRedo).accessibilityLabel(Text("Redo"))
                moreMenu
                if session.isEditing || titleFocused {
                    Button("Done") { titleFocused = false; session.endEditing() }
                        .fontWeight(.semibold)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if draft != nil { editingToolbar }
        }
        .onAppear {
            isVisible = true
            if draft == nil { draft = store.note(id: noteID) }
            if draft?.isBlank == true { titleFocused = true }
        }
        .onChange(of: draft) { _, value in
            guard isVisible, let value else { return }
            store.saveNote(value, retainingAttachments: session.retainedFiles)
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            addPhoto(item)
        }
        .onDisappear {
            // Commit composition before dropping the text view's callbacks.
            session.endEditing()
            isVisible = false
            if store.note(id: noteID) != nil, let draft {
                if store.saveNote(draft, retainingAttachments: session.retainedFiles) {
                    store.discardUnreferencedPhotos(session.retainedFiles)
                }
            } else {
                store.discardUnreferencedPhotos(session.retainedFiles)
            }
            session.onChange = nil
            session.onPhotoError = nil
            store.discardIfBlank(noteID)
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                session.endEditing()
                if store.deleteNote(noteID) { isVisible = false; dismiss() }
            }
        }
    }

    private func editor(_ note: Binding<Note>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Edited \(note.wrappedValue.updatedAt.formatted(.relative(presentation: .named)))")
                .font(NookFont.caption).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.top, 6)
            TextField("Title", text: note.title, axis: .vertical)
                .font(.system(.title, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .focused($titleFocused).submitLabel(.next)
                .onSubmit { titleFocused = false; session.beginEditing() }
                .accessibilityIdentifier("note.title")
                .padding(.horizontal, Metrics.screenPadding).padding(.top, 10)
            NoteTextEditor(runs: note.wrappedValue.editorRuns, session: session, attachments: store.attachments) { runs in
                guard isVisible else { return }
                note.wrappedValue.applyContent(runs)
            } onPhotoError: {
                photoFailed()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editingToolbar: some View {
        // Group's builder is nonisolated; capture UI state on the main actor first.
        let loadingPhoto = isLoadingPhoto
        return HStack(spacing: 26) {
            Menu {
                Button("Heading") { session.setStyle(.heading) }
                Button("Body") { session.setStyle(.body) }
                Divider()
                Button { session.toggleTrait(.traitBold) } label: { Label("Bold", systemImage: "bold") }
                Button { session.toggleTrait(.traitItalic) } label: { Label("Italic", systemImage: "italic") }
            } label: {
                Image(systemName: "textformat").frame(width: 36, height: 42)
            }
            .accessibilityLabel(Text("Text Format"))
            Button { titleFocused = false; session.toggleChecklist() } label: {
                Image(systemName: "checklist").frame(width: 36, height: 42)
            }
            .accessibilityLabel(Text("Checklist"))
            .accessibilityIdentifier("note.checklist")
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Group {
                    if loadingPhoto { ProgressView() }
                    else { Image(systemName: "photo.badge.plus") }
                }.frame(width: 36, height: 42)
            }
            .simultaneousGesture(TapGesture().onEnded { session.rememberPhotoSelection() })
            .disabled(loadingPhoto)
            .accessibilityLabel(Text("Add Photo"))
            Spacer(minLength: 0)
            Button { titleFocused = false; session.endEditing() } label: {
                Image(systemName: "keyboard.chevron.compact.down").frame(width: 36, height: 42)
            }
            .accessibilityLabel(Text("Hide Keyboard"))
        }
        .font(.system(size: 21))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 16).padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var moreMenu: some View {
        Menu {
            Menu {
                ForEach(NoteCategory.allCases, id: \.self) { category in
                    Button { draft?.category = category } label: {
                        Label(category.label, systemImage: draft?.category == category ? "checkmark" : category.symbol)
                    }
                }
            } label: { Label("Category", systemImage: "folder") }
            Button { draft?.isPinned.toggle() } label: {
                if draft?.isPinned == true { Label("Unpin", systemImage: "pin.slash") }
                else { Label("Pin", systemImage: "pin") }
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel(Text("More"))
    }

    private func addPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer { isLoadingPhoto = false; photoSelection = nil }
            guard let data = try? await item.loadTransferable(type: Data.self) else { photoFailed(); return }
            guard isVisible, store.note(id: noteID) != nil else { return }
            titleFocused = false
            session.insertPhoto(data, atSavedSelection: true)
        }
    }

    private func photoFailed() {
        router.showToast(ToastMessage(text: "Couldn't add the photo", symbol: "exclamationmark.triangle.fill", isWarning: true))
    }
}
