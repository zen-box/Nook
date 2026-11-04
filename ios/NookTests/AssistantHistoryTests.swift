import Foundation
import Testing
import NookCore
@testable import Nook

/// Assistant conversations are kept in the local database, restored after a restart, and never
/// exported.
@MainActor
struct AssistantHistoryTests {
    private func store(_ database: AppDatabase, defaults: UserDefaults) -> AppStore {
        AppStore(database: database, attachments: .makeTemporary(), defaults: defaults, vaultParameters: .testing)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "nook.history.tests.\(UUID())")!
    }

    private func taskPlan() throws -> AgentPlan {
        try AgentPlanner.prepare([.init(kind: .task, operation: .create, fields: ["title": .string("Buy milk")])],
                                 records: [], summary: "Add a task", currency: "CNY")
    }

    /// Stores a conversation as it is right after the assistant prepared `plan`.
    private func saveConversation(with plan: AgentPlan, in database: AppDatabase) throws {
        let snapshot = AgentHistorySnapshot(
            savedAt: Date(),
            entries: [
                .init(kind: .user, text: "HISTORY-MARKER add a task", imageCount: 0),
                .init(kind: .assistant, text: "Here is the draft."),
                .init(kind: .draft, plan: plan)
            ],
            draftStates: [plan.id: .pending],
            draftNotes: [:],
            answers: [:],
            pendingPlanID: plan.id,
            openQuestionID: nil,
            undoPlan: nil,
            undoablePlanID: nil,
            messages: [
                .init(AIMessage(role: "user", text: "HISTORY-MARKER add a task")),
                .init(AIMessage(role: "assistant", text: "Here is the draft."))
            ]
        )
        try database.setMetadata(NookJSON.makeEncoder().encode(snapshot), key: AppStore.assistantHistoryKey)
    }

    private func savedSnapshot(in database: AppDatabase) throws -> AgentHistorySnapshot? {
        try database.metadata(AppStore.assistantHistoryKey).map {
            try NookJSON.makeDecoder().decode(AgentHistorySnapshot.self, from: $0)
        }
    }

    @Test func aPendingDraftSurvivesARestartAndCanBeSavedThenUndone() throws {
        let db = try AppDatabase.makeInMemory(), settings = freshDefaults()
        let plan = try taskPlan()
        try saveConversation(with: plan, in: db)

        let first = store(db, defaults: settings)
        let session = first.assistantSession
        #expect(session.entries.count == 3)
        #expect(session.plan?.id == plan.id)
        #expect(session.state(of: plan) == .pending)
        session.confirm()
        #expect(first.tasks.map(\.title) == ["Buy milk"])
        #expect(try savedSnapshot(in: db)?.draftStates[plan.id] == .saved)

        // After another restart the saved draft is no longer pending but can still be undone.
        let second = store(db, defaults: settings)
        let restored = second.assistantSession
        #expect(restored.plan == nil)
        #expect(restored.undoablePlanID == plan.id)
        restored.undo()
        #expect(second.tasks.isEmpty)
        #expect(try savedSnapshot(in: db)?.draftStates[plan.id] == .undone)
    }

    @Test func turningHistoryOffDeletesTheSavedCopyAndClearingResets() throws {
        let db = try AppDatabase.makeInMemory(), settings = freshDefaults()
        let plan = try taskPlan()
        try saveConversation(with: plan, in: db)
        let store = store(db, defaults: settings)
        let session = store.assistantSession
        #expect(!session.isEmpty)

        store.keepsAssistantHistory = false
        #expect(try db.metadata(AppStore.assistantHistoryKey) == nil)
        session.discard()
        #expect(try db.metadata(AppStore.assistantHistoryKey) == nil)
        #expect(self.store(db, defaults: settings).assistantSession.isEmpty)

        // Turning it back on saves the open conversation again.
        store.keepsAssistantHistory = true
        #expect(try savedSnapshot(in: db)?.draftStates[plan.id] == .discarded)

        store.clearAssistantHistory()
        #expect(session.isEmpty)
        #expect(try db.metadata(AppStore.assistantHistoryKey) == nil)
        #expect(store.tasks.isEmpty)
    }

    @Test func historyIsNeverExported() throws {
        let db = try AppDatabase.makeInMemory()
        try saveConversation(with: try taskPlan(), in: db)
        let store = store(db, defaults: freshDefaults())
        #expect(!store.assistantSession.isEmpty)
        let exported = try JSONValue.from(store.portableValues()).json
        #expect(!exported.contains("HISTORY-MARKER"))
    }

    @Test func unreadableHistoryStartsAnEmptyConversation() throws {
        let db = try AppDatabase.makeInMemory()
        try db.setMetadata(Data("not json".utf8), key: AppStore.assistantHistoryKey)
        #expect(store(db, defaults: freshDefaults()).assistantSession.isEmpty)
    }

    @Test func imagesAreLeftOutAndTheModelIsToldSo() throws {
        let photo = AIImage(data: Data(repeating: 7, count: 4096))
        let stored = AgentHistorySnapshot.StoredMessage(AIMessage(role: "user", text: "What is this?", images: [photo]))
        let json = try NookJSON.makeEncoder().encode(stored)
        #expect(json.count < 1024)
        let restored = try NookJSON.makeDecoder().decode(AgentHistorySnapshot.StoredMessage.self, from: json).message
        #expect(restored.images.isEmpty)
        #expect(restored.text.hasPrefix("What is this?") && restored.text.contains("no longer available"))
    }

    @Test func trimmedContextStartsAtAUserMessage() {
        let call = AIToolCall(id: "1", name: "search_records", arguments: .object([:]))
        let messages = [
            AIMessage(role: "user", text: "Find lunch"),
            AIMessage(role: "assistant", calls: [call]),
            AIMessage(role: "tool", text: "{}", toolCallID: "1", toolName: "search_records"),
            AIMessage(role: "assistant", text: "Found it"),
            AIMessage(role: "user", text: "Delete it"),
            AIMessage(role: "assistant", text: "Draft ready")
        ]
        #expect(AgentHistorySnapshot.trimmed(messages, limit: 10) == messages)
        #expect(AgentHistorySnapshot.trimmed(messages, limit: 4).map(\.text) == ["Delete it", "Draft ready"])
        #expect(AgentHistorySnapshot.trimmed(messages, limit: 1).isEmpty)
    }
}
