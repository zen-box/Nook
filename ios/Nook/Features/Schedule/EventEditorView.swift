import SwiftUI
import NookCore

struct EventEditorView: View {
    enum Mode {
        case create(LocalDate)
        case edit(UUID)
    }

    let mode: Mode
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var category: EventCategory = .work
    @State private var isAllDay = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var loaded = false
    @State private var confirmDelete = false

    private var isEditing: Bool {
        switch mode {
        case .create: false
        case .edit: true
        }
    }

    private var components: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Location", text: $location)
                }
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(EventCategory.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                }
                Section {
                    Toggle("All day", isOn: $isAllDay)
                    DatePicker("Starts", selection: $start, displayedComponents: components)
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: components)
                }
                Section("Details") {
                    TextField("Add notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                if isEditing {
                    Section {
                        Button("Delete Event", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isEditing ? Text("Edit Event") : Text("New Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Event", role: .destructive) {
                    deleteAndClose()
                }
            }
        }
        .onAppear { load() }
        .onChange(of: start) { _, newStart in
            if end < newStart {
                end = newStart.addingTimeInterval(3600)
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .create(let day):
            let isToday = day == LocalDate.today(in: store.timeZone)
            let hour = isToday ? min(Calendar.current.component(.hour, from: Date()) + 1, 23) : 9
            start = day.date(hour: hour, in: store.timeZone)
            end = start.addingTimeInterval(3600)
        case .edit(let id):
            guard let event = store.event(id: id) else { return }
            title = event.title
            location = event.location ?? ""
            notes = event.notes
            category = event.category
            isAllDay = event.isAllDay
            start = event.start
            if event.isAllDay {
                // Stored ends are exclusive (next midnight); show the last day instead.
                end = max(event.effectiveEnd.addingTimeInterval(-1), event.start)
            } else {
                end = event.end ?? event.start.addingTimeInterval(3600)
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let zone = store.timeZone
        let eventStart: Date
        let eventEnd: Date
        if isAllDay {
            let firstDay = LocalDate(start, timeZone: zone)
            let lastDay = max(LocalDate(end, timeZone: zone), firstDay)
            eventStart = firstDay.startDate(in: zone)
            eventEnd = lastDay.adding(days: 1).startDate(in: zone)
        } else {
            eventStart = start
            eventEnd = max(end, start)
        }
        var event: ScheduleEvent
        switch mode {
        case .create:
            event = ScheduleEvent(title: trimmed, start: eventStart)
        case .edit(let id):
            guard let existing = store.event(id: id) else {
                dismiss()
                return
            }
            event = existing
        }
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.title = trimmed
        event.start = eventStart
        event.end = eventEnd
        event.isAllDay = isAllDay
        event.location = place.isEmpty ? nil : place
        event.notes = notes
        event.category = category
        store.saveEvent(event)
        router.selectedDay = LocalDate(eventStart, timeZone: zone)
        dismiss()
    }

    private func deleteAndClose() {
        if case .edit(let id) = mode {
            store.deleteEvent(id)
        }
        dismiss()
    }
}
