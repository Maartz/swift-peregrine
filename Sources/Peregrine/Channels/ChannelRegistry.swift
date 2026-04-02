import Foundation

/// The shared hub that tracks live sockets per topic and fans out broadcasts.
///
/// Uses `@unchecked Sendable` with an `NSLock` so registration and unregistration
/// are synchronous — allowing `TestChannelSocket.deinit` to clean up without `await`.
public final class ChannelRegistry: @unchecked Sendable {

    // MARK: - State

    public var router: ChannelRouter
    private let lock = NSLock()
    private var sockets: [String: [UUID: ChannelSocket]] = [:]
    private var presenceState: [String: [String: ChannelPayload]] = [:]

    // MARK: - Init

    public init(router: ChannelRouter = ChannelRouter()) {
        self.router = router
    }

    // MARK: - Registration (synchronous)

    /// Registers a socket as a subscriber for `topic`.
    public func register(_ socket: ChannelSocket, topic: String) {
        lock.withLock {
            socket.topic = topic
            if sockets[topic] == nil { sockets[topic] = [:] }
            sockets[topic]![socket.id] = socket
        }
    }

    /// Removes a socket from `topic` subscriptions.
    public func unregister(_ socket: ChannelSocket, topic: String) {
        _ = lock.withLock {
            sockets[topic]?.removeValue(forKey: socket.id)
        }
    }

    // MARK: - Presence (synchronous)

    public func trackPresence(socketID: UUID, topic: String, key: String, meta: ChannelPayload) {
        lock.withLock {
            if presenceState[topic] == nil { presenceState[topic] = [:] }
            presenceState[topic]![key] = meta
        }
    }

    public func untrackPresence(topic: String, key: String) {
        _ = lock.withLock {
            presenceState[topic]?.removeValue(forKey: key)
        }
    }

    public func listPresence(topic: String) -> [String: ChannelPayload] {
        lock.withLock { presenceState[topic] ?? [:] }
    }

    // MARK: - Broadcast (internal — from ChannelSocket)

    /// Delivers an event to all sockets on `topic`, optionally excluding the sender.
    /// Runs the channel's `intercept` hook if the event is registered for interception.
    func deliver(
        topic: String,
        event: String,
        payload: ChannelPayload,
        from sender: ChannelSocket,
        excludeSender: Bool
    ) async throws {
        var deliveryPayload = payload

        // Run intercept if the channel type wants to intercept this event
        if let handlerType = router.handlerType(for: topic),
           handlerType.intercepts.contains(event) {
            let handler = handlerType.init()
            deliveryPayload = try await handler.intercept(event: event, payload: payload, socket: sender)
        }

        let targets = lock.withLock {
            sockets[topic].map { Array($0.values) } ?? []
        }
        for socket in targets {
            if excludeSender && socket.id == sender.id { continue }
            socket.deliverHandler(event, deliveryPayload)
        }
    }

    // MARK: - Broadcast (public — server push, no sender)

    /// Broadcasts an event to all sockets on `topic` from outside a handler (e.g. background job).
    /// Does not run intercept hooks.
    public func broadcast(topic: String, event: String, payload: ChannelPayload) async throws {
        let targets = lock.withLock {
            sockets[topic].map { Array($0.values) } ?? []
        }
        for socket in targets {
            socket.deliverHandler(event, payload)
        }
    }
}
