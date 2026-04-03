import Foundation
import Nexus
import Crypto

// MARK: - Session Key

/// Typed assign key for the session store injected by the session plug.
public enum PeregrineSessionKey: AssignKey {
    public typealias Value = any SessionStore
}

// MARK: - Session ID cookie

/// Default session cookie name.
public let defaultSessionCookie = "_peregrine_session"
/// Default session TTL (24 hours).
public let defaultSessionTTL: Duration = .seconds(24 * 3600)

// MARK: - Secure Random ID Generator

/// Generates a URL-safe, cryptographically random session identifier.
private func generateSessionID() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// MARK: - SessionPendingOps

/// Accumulated session operations to apply during `beforeSend`.
/// Only records *what* to do — the actual store writes happen via
/// `Connection.flushSession()` or the framework's response pipeline.
struct SessionPendingOps: Sendable {
    var writes: [String: AnySendableBox] = [:]
    var deleteKeys: Set<String> = []
    var clearAll = false
    var renewToNewID: String?
    var renewOldID: String?
}

/// Type-erased box for session values.
struct AnySendableBox: Sendable {
    let value: any Sendable
}

// MARK: - SessionPlug

/// A plug that initializes session management via a ``SessionStore`` backend.
///
/// The plug loads session data on the way in. Writes queued by
/// ``Connection/putSessionValue(_:_)`` are recorded in pending ops and
/// persisted to the store when the connection reaches the ``beforeSend``
/// lifecycle hook. Because the hook is synchronous and the SessionStore
/// API is async, persistence happens via fire-and-forget `Task` — which
/// is acceptable because session writes are best-effort (the session
/// cookie will still be set on the response even if the store write is
/// slightly delayed).
///
/// For testing, use ``Connection/flushSession()`` to force persistence
/// before making assertions.
public func session(
    store: SessionStore,
    cookieName: String = defaultSessionCookie,
    ttl: Duration = defaultSessionTTL
) -> Plug {
    { conn in
        var result = conn

        // Inject the store and configuration into assigns
        result = result.assign(SessionCookieNameKey.self, value: cookieName)
        result = result.assign(PeregrineSessionKey.self, value: store)
        result = result.assign(SessionTTLKey.self, value: ttl)
        result = result.assign(SessionPendingOpsKey.self, value: SessionPendingOps())

        // Extract session ID from cookie or generate new one
        let existingSessID = conn.reqCookies[cookieName]
        var sessionID: String

        if existingSessID != nil && !existingSessID!.isEmpty {
            sessionID = existingSessID!

            // Load session data from store
            if let data = try? await store.get(sessionID) {
                result = result.assign(SessionDataKey.self, value: data)
            }
        } else {
            sessionID = generateSessionID()
            // Mark that we need to set the Set-Cookie header
            result = result.assign(NewSessionIDKey.self, value: sessionID)
        }

        // Track session ID
        result = result.assign(SessionIDKey.self, value: sessionID)

        // Capture values for closure
        let _sessionID = sessionID
        let _ttl = ttl
        let _cn = cookieName

        // Register beforeSend: record ops and set cookie headers
        // The actual store writes happen via fire-and-forget Task.
        result = result.registerBeforeSend { c in
            var conn = c

            // Set cookie header for new sessions
            if let newID = conn[NewSessionIDKey.self] {
                conn = conn.putRespHeader(
                    HTTPField.Name.setCookie,
                    "\(_cn)=\(newID); Path=/; HttpOnly"
                )
            }

            let ops = conn[SessionPendingOpsKey.self] ?? SessionPendingOps()

            // Set cookie header for clearance
            if ops.clearAll {
                Task { try? await store.delete(_sessionID) }
                return conn.putRespHeader(
                    HTTPField.Name.setCookie,
                    "\(_cn)=deleted; Path=/; HttpOnly; Max-Age=0"
                )
            }

            // Set cookie header for renewal
            if let renewID = ops.renewToNewID {
                if let oldID = ops.renewOldID, oldID != renewID {
                    let o = oldID
                    Task { try? await store.delete(o) }
                }
                if let data = conn[SessionDataKey.self] {
                    let d = data
                    Task { try? await store.set(renewID, data: d, ttl: _ttl) }
                }
                return conn.putRespHeader(
                    HTTPField.Name.setCookie,
                    "\(_cn)=\(renewID); Path=/; HttpOnly"
                )
            }

            // Apply pending deletes to session data
            if !ops.deleteKeys.isEmpty {
                if var current = conn[SessionDataKey.self] {
                    for key in ops.deleteKeys {
                        current.removeValue(forKey: key)
                    }
                    conn = conn.assign(SessionDataKey.self, value: current)
                }
            }

            // Apply pending writes
            if !ops.writes.isEmpty {
                var merged = conn[SessionDataKey.self] ?? [:]
                for (key, boxed) in ops.writes {
                    merged[key] = boxed.value
                }
                conn = conn.assign(SessionDataKey.self, value: merged)

                let sid = _sessionID
                let m = merged
                Task { try? await store.set(sid, data: m, ttl: _ttl) }
            }

            return conn
        }

        return result
    }
}

// MARK: - Session Assign Keys

private enum SessionPlugStoreKey: AssignKey {
    typealias Value = any SessionStore
}

private enum SessionCookieNameKey: AssignKey {
    typealias Value = String
}

private enum SessionTTLKey: AssignKey {
    typealias Value = Duration
}

private enum SessionIDKey: AssignKey {
    typealias Value = String
}

private enum NewSessionIDKey: AssignKey {
    typealias Value = String
}

enum SessionDataKey: AssignKey {
    typealias Value = [String: any Sendable]
}

private enum SessionPendingOpsKey: AssignKey {
    typealias Value = SessionPendingOps
}

enum SessionClearKey: AssignKey {
    typealias Value = Bool
}

struct SessionRenewInfo: Sendable {
    let newID: String
    let oldID: String?
}

enum SessionRenewKey: AssignKey {
    typealias Value = SessionRenewInfo
}

// MARK: - Connection Extensions — session helpers

extension Connection {

    /// Retrieves a value from the server-side session store.
    public func sessionValue(_ key: String) -> (any Sendable)? {
        self[SessionDataKey.self]?[key]
    }

    /// Queues a value to be written to the session store.
    public func putSessionValue(_ key: String, _ value: some Sendable) -> Connection {
        var ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()
        ops.writes[key] = AnySendableBox(value: value)
        return assign(SessionPendingOpsKey.self, value: ops)
    }

    /// Queues removal of a key from the session store.
    public func deleteSessionValue(_ key: String) -> Connection {
        var ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()
        ops.deleteKeys.insert(key)
        return assign(SessionPendingOpsKey.self, value: ops)
    }

    /// Queues the session to be cleared and its cookie removed.
    public func clearSessionID() -> Connection {
        var ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()
        ops.clearAll = true
        return assign(SessionPendingOpsKey.self, value: ops)
    }

    /// Generates a new session ID while preserving current session data.
    public func renewSessionID() -> Connection {
        let oldID = self[SessionIDKey.self]
        let newID = generateSessionID()

        var ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()
        ops.renewToNewID = newID
        ops.renewOldID = oldID

        return assign(SessionIDKey.self, value: newID)
            .assign(SessionPendingOpsKey.self, value: ops)
    }

    /// Flushes all pending session writes to the store immediately.
    /// Useful in tests to ensure persistence before making assertions.
    public func flushSession() async throws {
        guard let sessionID = self[SessionIDKey.self],
              let store = self[PeregrineSessionKey.self],
              let ttl = self[SessionTTLKey.self]
        else { return }

        let ops = self[SessionPendingOpsKey.self] ?? SessionPendingOps()

        if ops.clearAll {
            try await store.delete(sessionID)
            return
        }

        if let renewID = ops.renewToNewID {
            if let oldID = ops.renewOldID, oldID != renewID {
                try await store.delete(oldID)
            }
            if let data = self[SessionDataKey.self] {
                try await store.set(renewID, data: data, ttl: ttl)
            }
            return
        }

        // Apply deletes
        if !ops.deleteKeys.isEmpty {
            if var current = self[SessionDataKey.self] {
                for key in ops.deleteKeys {
                    current.removeValue(forKey: key)
                }
                try await store.set(sessionID, data: current, ttl: ttl)
                return
            }
        }

        // Apply writes
        if !ops.writes.isEmpty {
            var merged = self[SessionDataKey.self] ?? [:]
            for (key, boxed) in ops.writes {
                merged[key] = boxed.value
            }
            try await store.set(sessionID, data: merged, ttl: ttl)
        }
    }
}
