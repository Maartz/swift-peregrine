import Foundation
import HTTPTypes
import Nexus
import NexusTest
import Testing

@testable import Peregrine

// MARK: - Helpers

/// Builds a connection with a Cookie request header containing the given session ID.
private func connWithCookie(_ sessionID: String, cookieName: String = "_peregrine_session") -> Connection {
    var conn = TestConnection.build()
    conn = conn.putReqHeader(HTTPField.Name("Cookie")!, "\(cookieName)=\(sessionID)")
    return conn
}

/// Helper extracting all Set-Cookie response header values.
private func sessionSetCookieHeaders(_ conn: Connection) -> [String] {
    conn.response.headerFields.filter { $0.name == HTTPField.Name("Set-Cookie")! }.map(\.value)
}

// MARK: - Tests

@Suite("Sessions")
struct SessionTests {

    @Test("new connection gets a session ID cookie")
    func newConnectionGetsCookie() async throws {
        let store = MemorySessionStore()
        let conn = TestConnection.build()
        let plug = session(store: store)
        let afterPlug = try await plug(conn)
        let sent = afterPlug.runBeforeSend()

        let cookies = sessionSetCookieHeaders(sent)
        #expect(cookies.count == 1)
        #expect(cookies[0].hasPrefix("_peregrine_session="))
    }

    @Test("value can be stored and retrieved")
    func storeAndRetrieve() async throws {
        let store = MemorySessionStore()
        let sessionID = UUID().uuidString
        try await store.set(sessionID, data: ["user_id": 42], ttl: nil)

        let conn = connWithCookie(sessionID)
        let plug = session(store: store)
        let afterPlug = try await plug(conn)

        // Verify session data was loaded
        #expect(afterPlug.sessionValue("user_id") as? Int == 42)
    }

    @Test("putSessionValue queues writes")
    func putSessionValue() async throws {
        let store = MemorySessionStore()
        let sessionID = UUID().uuidString
        try await store.set(sessionID, data: [:], ttl: nil)

        let plug = session(store: store)
        let afterPlug = try await plug(connWithCookie(sessionID))

        // Handler writes
        let withWrite = afterPlug.putSessionValue("user_id", 42)
        let sent = withWrite.runBeforeSend()

        // Flush manually since beforeSend only fire-and-forgets
        try await sent.flushSession()

        // Verify it was persisted
        let loaded = try await store.get(sessionID)
        #expect(loaded?["user_id"] as? Int == 42)
    }

    @Test("deleteSessionValue removes a key")
    func deleteSessionValue() async throws {
        let store = MemorySessionStore()
        let sessionID = UUID().uuidString
        try await store.set(sessionID, data: ["user_id": 42, "name": "test"], ttl: nil)

        let plug = session(store: store)
        let afterPlug = try await plug(connWithCookie(sessionID))

        #expect(afterPlug.sessionValue("user_id") as? Int == 42)

        let withDelete = afterPlug.deleteSessionValue("user_id")
        try await withDelete.flushSession()

        let loaded = try await store.get(sessionID)
        #expect(loaded?["user_id"] == nil)
        #expect(loaded?["name"] as? String == "test")
    }

    @Test("clearSessionID deletes session and removes cookie")
    func clearSessionID() async throws {
        let store = MemorySessionStore()
        let sessionID = UUID().uuidString
        try await store.set(sessionID, data: ["user_id": 42], ttl: nil)

        let plug = session(store: store)
        let afterPlug = try await plug(connWithCookie(sessionID))

        let cleared = afterPlug.clearSessionID()
        let sent = cleared.runBeforeSend()
        try await sent.flushSession()

        // Session should be deleted
        let loaded = try await store.get(sessionID)
        #expect(loaded == nil)

        // Cookie should be set for deletion
        let cookies = sessionSetCookieHeaders(sent)
        #expect(cookies.count == 1)
        #expect(cookies[0].contains("Max-Age=0"))
    }

    @Test("renewSessionID generates new ID and preserves data")
    func renewSessionID() async throws {
        let store = MemorySessionStore()
        let oldID = UUID().uuidString
        try await store.set(oldID, data: ["user_id": 42], ttl: nil)

        let plug = session(store: store)
        let afterPlug = try await plug(connWithCookie(oldID))

        #expect(afterPlug.sessionValue("user_id") as? Int == 42)

        let renewed = afterPlug.renewSessionID()
        let sent = renewed.runBeforeSend()
        try await sent.flushSession()

        // Old session should be deleted
        let oldData = try await store.get(oldID)
        #expect(oldData == nil)

        // New cookie should be set
        let cookies = sessionSetCookieHeaders(sent)
        #expect(cookies.count == 1)
        #expect(cookies[0].hasPrefix("_peregrine_session="))
        #expect(!cookies[0].contains(oldID))
    }

    @Test("session cleanup removes expired entries")
    func sessionCleanup() async throws {
        let store = MemorySessionStore()

        // Set a session with short TTL
        try await store.set("short_live", data: ["key": "value"], ttl: .milliseconds(10))

        // Should exist immediately
        let before = try await store.get("short_live")
        #expect(before != nil)

        // Wait for expiry
        try await Task.sleep(for: .milliseconds(50))

        // Should be expired now
        let after = try await store.get("short_live")
        #expect(after == nil)
    }
}
