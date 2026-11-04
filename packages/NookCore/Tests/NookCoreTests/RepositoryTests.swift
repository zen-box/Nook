import Foundation
import Testing
@testable import NookCore

struct RepositoryTests {
    private func note(_ title: String) -> Note {
        Note(title: title, category: .life, createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test func keepsInsertionOrder() async {
        let repository = InMemoryRepository<Note>()
        for title in ["B", "A", "C"] {
            await repository.upsert(note(title))
        }
        #expect(await repository.all().map(\.title) == ["B", "A", "C"])
        #expect(await repository.count == 3)
    }

    @Test func upsertReplacesInPlace() async {
        var a = note("A")
        let repository = InMemoryRepository([a, note("B")])
        a.title = "A2"
        await repository.upsert(a)
        #expect(await repository.all().map(\.title) == ["A2", "B"])
        #expect(await repository.record(id: a.id)?.title == "A2")
    }

    @Test func deletes() async {
        let a = note("A")
        let repository = InMemoryRepository([a, note("B")])
        await repository.delete(id: a.id)
        await repository.delete(id: UUID())  // missing: nothing happens
        #expect(await repository.all().map(\.title) == ["B"])
        #expect(await repository.record(id: a.id) == nil)
        await repository.upsert(a)
        #expect(await repository.all().map(\.title) == ["B", "A"])
    }

    @Test func initialRecordsWithTheSameIdKeepTheLastValue() async {
        var a = note("A")
        let first = a
        a.title = "A again"
        let repository = InMemoryRepository([first, note("B"), a])
        #expect(await repository.count == 2)
        #expect(await repository.all().map(\.title) == ["A again", "B"])
    }

    @Test func worksThroughTheProtocol() async throws {
        let repository: any Repository<Note> = InMemoryRepository<Note>()
        let a = note("A")
        try await repository.upsert(a)
        #expect(try await repository.all().map(\.id) == [a.id])
        #expect(try await repository.record(id: a.id) == a)
    }
}
