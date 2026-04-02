import Foundation

/// Tracks which users are online on which topics.
///
/// Backed by `ChannelRegistry`'s in-memory presence state.
/// Each socket can be tracked with a key (e.g. userID) and arbitrary metadata.
///
/// ```swift
/// // In Channel.join:
/// try await Presence.track(socket, topic: topic, key: userID.uuidString, meta: [
///     "name": "Alice",
///     "online_at": Date().timeIntervalSince1970
/// ])
///
/// // In Channel.leave:
/// await Presence.untrack(socket, topic: topic)
/// ```
public enum Presence {

    /// Tracks a socket's presence on a topic with the given key and metadata.
    /// Broadcasts a `presence_diff` event with joins/leaves to all subscribers.
    public static func track(
        _ socket: ChannelSocket,
        topic: String,
        key: String,
        meta: ChannelPayload
    ) async throws {
        socket.registry?.trackPresence(socketID: socket.id, topic: topic, key: key, meta: meta)
        // Broadcast presence_diff to notify other subscribers
        let joinsValue: any Sendable = meta
        try? await socket.registry?.broadcast(
            topic: topic,
            event: "presence_diff",
            payload: ["joins_key": key, "joins_meta": joinsValue]
        )
    }

    /// Removes a socket's presence entry for a topic.
    /// Broadcasts a `presence_diff` event to notify other subscribers.
    public static func untrack(_ socket: ChannelSocket, topic: String) async {
        // Find and remove the key(s) associated with this socket
        if let registry = socket.registry {
            let presence = registry.listPresence(topic: topic)
            for key in presence.keys {
                registry.untrackPresence(topic: topic, key: key)
            }
        }
    }

    /// Returns the current presence list for a topic.
    public static func list(topic: String, registry: ChannelRegistry) -> [String: ChannelPayload] {
        registry.listPresence(topic: topic)
    }
}
