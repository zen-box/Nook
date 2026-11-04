import SwiftUI
import NookCore

struct TripEditorView: View {
    let tripID: UUID?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var destination = ""
    @State private var summary = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3 * 86_400)
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name", text: $title)
                    TextField("Destination", text: $destination)
                }
                Section {
                    DatePicker("Starts", selection: $start, displayedComponents: .date)
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
                }
                Section("Details") {
                    TextField("What's the plan?", text: $summary, axis: .vertical)
                        .lineLimit(3...)
                } footer: {
                    Text("A trip groups related events. To receive reminders, add timed events to it and set their reminder times.")
                }
                if tripID != nil {
                    Section {
                        Button("Delete Trip", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(tripID == nil ? Text("New Trip") : Text("Edit Trip"))
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
            .confirmationDialog("Delete this trip?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Trip", role: .destructive) {
                    if let tripID {
                        guard store.deleteTrip(tripID) else { return }
                    }
                    dismiss()
                }
            } message: {
                Text("Its events and plan note are kept.")
            }
        }
        .onAppear { load() }
        .onChange(of: start) { _, newStart in
            if end < newStart {
                end = newStart
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let tripID, let trip = store.trip(id: tripID) else { return }
        title = trip.title
        destination = trip.destination ?? ""
        summary = trip.summary
        start = trip.startDate.noon
        end = trip.endDate.noon
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let zone = store.timeZone
        let first = LocalDate(start, timeZone: zone)
        let last = max(LocalDate(end, timeZone: zone), first)
        var trip: TripPlan
        if let tripID, let existing = store.trip(id: tripID) {
            trip = existing
        } else {
            trip = TripPlan(title: trimmed, startDate: first, endDate: last)
        }
        let place = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.title = trimmed
        trip.destination = place.isEmpty ? nil : place
        trip.startDate = first
        trip.endDate = last
        trip.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.saveTrip(trip) else { return }
        dismiss()
    }
}

struct AnniversaryEditorView: View {
    let anniversaryID: UUID?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var kind: AnniversaryKind = .birthday
    @State private var repeatsYearly = true
    @State private var notes = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title)
                    Picker("Type", selection: $kind) {
                        ForEach(AnniversaryKind.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Repeats every year", isOn: $repeatsYearly)
                } footer: {
                    Text("Use the original date, such as the date of birth, to see how many years it has been.")
                    Text("Anniversaries show a countdown; they don't send notifications yet.")
                }
                Section("Details") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                if anniversaryID != nil {
                    Section {
                        Button("Delete Anniversary", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(anniversaryID == nil ? Text("New Anniversary") : Text("Edit Anniversary"))
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
            .confirmationDialog("Delete this anniversary?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Anniversary", role: .destructive) {
                    if let anniversaryID {
                        guard store.deleteAnniversary(anniversaryID) else { return }
                    }
                    dismiss()
                }
            }
        }
        .onAppear { load() }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let anniversaryID, let anniversary = store.anniversary(id: anniversaryID) else { return }
        title = anniversary.title
        date = anniversary.date.noon
        kind = anniversary.kind
        repeatsYearly = anniversary.repeatRule == .yearly
        notes = anniversary.notes
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let day = LocalDate(date, timeZone: store.timeZone)
        var anniversary: Anniversary
        if let anniversaryID, let existing = store.anniversary(id: anniversaryID) {
            anniversary = existing
        } else {
            anniversary = Anniversary(title: trimmed, date: day)
        }
        anniversary.title = trimmed
        anniversary.date = day
        anniversary.kind = kind
        anniversary.repeatRule = repeatsYearly ? .yearly : .never
        anniversary.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.saveAnniversary(anniversary) else { return }
        dismiss()
    }
}
