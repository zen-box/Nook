import SwiftUI
import NookCore

@MainActor
struct TasksView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var edited: TaskItem?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if store.tasks.isEmpty { Text("No tasks yet. Add one or ask Nook Assistant.").foregroundStyle(Theme.textSecondary) }
                ForEach(store.tasks.sorted { ($0.isCompleted ? 1 : 0, $0.dueAt ?? .distantFuture) < ($1.isCompleted ? 1 : 0, $1.dueAt ?? .distantFuture) }) { task in
                    HStack {
                        Button {
                            var copy = task; copy.isCompleted.toggle()
                            if !store.saveTask(copy) { error = String(localized: "Couldn't save the change") }
                        } label: { Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain)
                        Button { edited = task } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: task.title).strikethrough(task.isCompleted).foregroundStyle(Theme.textPrimary)
                                if let date = task.dueAt { Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(Theme.textSecondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: task.title))
                            .accessibilityIdentifier("task.edit.\(task.id)")
                    }
                }
                if let error { Text(verbatim: error).foregroundStyle(Pastel.rose.strong) }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { edited = TaskItem(title: "") } label: { Image(systemName: "plus") }.accessibilityIdentifier("task.add") }
            }
            .sheet(item: $edited) { task in TaskEditorView(initial: task).environment(store).modifier(AppAppearance()) }
        }
    }
}

@MainActor
private struct TaskEditorView: View {
    let initial: TaskItem
    @State private var task = TaskItem(title: "")
    @State private var error: String?
    @State private var deleting = false
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $task.title).accessibilityIdentifier("task.title")
                TextField("Notes", text: $task.notes, axis: .vertical)
                Toggle("Due Date", isOn: Binding(get: { task.dueAt != nil }, set: { task.dueAt = $0 ? Date() : nil; if !$0 { task.reminderMinutes = nil } }))
                if task.dueAt != nil {
                    DatePicker("Due", selection: Binding(get: { task.dueAt ?? Date() }, set: { task.dueAt = $0 }))
                    Picker("Reminder", selection: $task.reminderMinutes) {
                        Text("None").tag(Int?.none)
                        ForEach(EventEditorView.reminderOptions, id: \.self) { Text(EventEditorView.reminderLabel($0)).tag(Int?.some($0)) }
                    }
                }
                Toggle("Completed", isOn: $task.isCompleted)
                if store.tasks.contains(where: { $0.id == task.id }) {
                    Button("Delete Task", role: .destructive) { deleting = true }
                }
                if let error { Text(verbatim: error).foregroundStyle(Pastel.rose.strong) }
            }
            .navigationTitle("Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.saveTask(task) { dismiss() } else { error = String(localized: "Couldn't save the change") }
                }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("task.save") }
            }
            .confirmationDialog("Delete this task?", isPresented: $deleting) { Button("Delete Task", role: .destructive) {
                do { try store.deleteTask(task.id); dismiss() } catch { self.error = error.localizedDescription }
            } }
        }.onAppear { task = initial }
    }
}
