import SwiftUI
import NookCore

enum NoteFilter: Hashable {
    case all
    case category(NoteCategory)
    case pinned
}

enum NoteSort: String, CaseIterable, Identifiable {
    case recent, title

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .recent: "Recently edited"
        case .title: "Title"
        }
    }
}

struct NotesView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var filter: NoteFilter = .all
    @State private var sort: NoteSort = .recent

    var body: some View {
        let notes = visibleNotes
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                ScreenHeader(title: "Notes") {
                    AddMenuButton(primary: .note)
                }
                HStack(spacing: 10) {
                    SearchField(prompt: "Search notes", text: $search)
                    sortMenu
                }
                .padding(.horizontal, Metrics.screenPadding)
                chips
                if notes.isEmpty {
                    EmptyStateView(
                        symbol: "note.text",
                        title: search.isEmpty ? "No notes yet" : "No matching notes",
                        message: search.isEmpty ? "Tap + to write your first note." : "Try another word or category."
                    )
                    .card()
                    .padding(.horizontal, Metrics.screenPadding)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(notes) { note in
                            NoteCard(note: note)
                        }
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, Metrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) { StatusBarScrim() }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("screen.notes")
    }

    private var visibleNotes: [Note] {
        var notes: [Note]
        switch filter {
        case .all:
            notes = NoteQuery.filter(store.notes, search: search)
        case .category(let category):
            notes = NoteQuery.filter(store.notes, search: search, category: category)
        case .pinned:
            notes = NoteQuery.filter(store.notes, search: search).filter(\.isPinned)
        }
        notes.removeAll { $0.isBlank }
        if sort == .title {
            notes.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
        return notes
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Chip(title: "All", isSelected: filter == .all) {
                    filter = .all
                }
                ForEach([NoteCategory.work, .travel, .life], id: \.self) { category in
                    Chip(title: category.label, isSelected: filter == .category(category)) {
                        filter = .category(category)
                    }
                }
                Menu {
                    Button {
                        filter = .category(.personal)
                    } label: {
                        Label("Personal", systemImage: NoteCategory.personal.symbol)
                    }
                    Button {
                        filter = .pinned
                    } label: {
                        Label("Pinned", systemImage: "pin")
                    }
                } label: {
                    moreChip
                }
                .accessibilityLabel(Text("More filters"))
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var moreChip: some View {
        switch filter {
        case .category(.personal):
            ChipLabel(title: "Personal", isSelected: true)
        case .pinned:
            ChipLabel(title: "Pinned", symbol: "pin.fill", isSelected: true)
        default:
            ChipLabel(title: nil, symbol: "ellipsis", isSelected: false)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(NoteSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 46, height: 46)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
                .shadow(color: Theme.shadow, radius: 10, x: 0, y: 4)
        }
        .accessibilityLabel(Text("Sort notes"))
    }
}

struct NoteCard: View {
    let note: Note

    var body: some View {
        NavigationLink(value: AppRoute.note(note.id)) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if !note.checklist.isEmpty || note.hasImage {
                    HStack(alignment: .top, spacing: 12) {
                        if !note.checklist.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(Array(note.checklist.prefix(4))) { item in
                                    ChecklistLine(item: item)
                                }
                                if note.checklist.count > 4 {
                                    Text("+\(note.checklist.count - 4) more")
                                        .font(NookFont.micro)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        } else if !note.preview.isEmpty {
                            previewText
                        }
                        Spacer(minLength: 0)
                        if note.hasImage {
                            FujiThumbnail()
                                .frame(width: 92, height: 92)
                        }
                    }
                } else if !note.preview.isEmpty {
                    previewText
                }
            }
            .card()
        }
        .buttonStyle(.pressable)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(symbol: note.category.symbol, pastel: note.category.pastel)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(NookFont.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(note.updatedAt, format: .dateTime.month(.abbreviated).day())
                    Text(verbatim: "·")
                    Text(note.category.label)
                }
                .font(NookFont.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Pastel.blue.base)
                    .rotationEffect(.degrees(45))
                    .accessibilityLabel(Text("Pinned"))
            } else {
                Chevron()
            }
        }
    }

    private var previewText: some View {
        Text(note.preview)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}

struct ChecklistLine: View {
    let item: ChecklistItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(item.isDone ? Pastel.mint.strong : Theme.textTertiary)
            Text(item.text)
                .font(.subheadline)
                .strikethrough(item.isDone, color: Theme.textTertiary)
                .foregroundStyle(item.isDone ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isDone ? .isSelected : [])
    }
}
