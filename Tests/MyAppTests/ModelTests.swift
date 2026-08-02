import Foundation
import Testing

@testable import MyApp

@Suite("Domain models")
nonisolated struct ModelTests {
    @Test("Checkpoint round-trips through JSON")
    func checkpointCodable() throws {
        let checkpoint = Checkpoint(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            note: "with a note"
        )
        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(Checkpoint.self, from: data)
        #expect(decoded == checkpoint)
    }

    @Test("a note-less Checkpoint round-trips too")
    func checkpointWithoutNote() throws {
        let checkpoint = Checkpoint(note: nil)
        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(Checkpoint.self, from: data)
        #expect(decoded == checkpoint)
        #expect(decoded.note == nil)
    }

    @Test("Checkpoint.id is the Identifiable conformance")
    func checkpointIdentity() {
        let id = UUID()
        #expect(Checkpoint(id: id).id == id)
    }

    @Test("isToday follows the calendar, not the clock")
    func checkpointIsToday() throws {
        #expect(Checkpoint().isToday)

        let yesterday = try #require(
            Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )
        #expect(Checkpoint(timestamp: yesterday).isToday == false)
    }

    @Test("SessionState.isActive follows startedAt")
    func sessionActivity() {
        #expect(SessionState.idle.isActive == false)
        #expect(SessionState(startedAt: .now).isActive)
    }

    @Test("SessionState encodes only its stored property")
    func sessionEncodesStoredPropertyOnly() throws {
        let state = SessionState(startedAt: Date(timeIntervalSince1970: 1_000))
        let data = try JSONEncoder().encode(state)
        let object = try JSONSerialization.jsonObject(with: data)
        let dictionary = try #require(object as? [String: Any])

        // `isActive` is computed; leaking it into the payload would make the
        // wire format lie about what is authoritative.
        #expect(Set(dictionary.keys) == ["startedAt"])
    }

    @Test("SessionState round-trips through JSON")
    func sessionCodable() throws {
        let state = SessionState(startedAt: Date(timeIntervalSince1970: 2_000))
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)
        #expect(decoded == state)
    }
}
