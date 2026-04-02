import Foundation
import HTTPTypes
import Nexus
import NexusRouter
import NexusTest
import Peregrine
import Spectro

/// A test harness that runs requests through a ``PeregrineApp`` pipeline
/// without starting a server.
///
/// ```swift
/// @Test func listDonuts() async throws {
///     let app = try TestApp(DonutShop.self)
///     let response = try await app.get("/api/v1/donuts")
///     #expect(response.status == .ok)
/// }
/// ```
// MARK: - Shared channel registry per App type

/// Thread-safe storage for per-App.Type channel registries.
/// Allows multiple `TestApp<ChatApp>` instances to share the same `ChannelRegistry`
/// so sockets from different instances can exchange broadcasts.
private enum SharedChannelRegistry {
    nonisolated(unsafe) static var lock = NSLock()
    nonisolated(unsafe) static var registries: [ObjectIdentifier: ChannelRegistry] = [:]

    static func registry(for typeID: ObjectIdentifier, router: ChannelRouter) -> ChannelRegistry {
        lock.withLock {
            if let existing = registries[typeID] { return existing }
            let r = ChannelRegistry(router: router)
            registries[typeID] = r
            return r
        }
    }
}

// MARK: - TestApp

public struct TestApp<App: PeregrineApp>: Sendable {

    private let plug: Plug

    /// The PubSub adapter injected into the pipeline, if configured.
    /// Use this in tests to subscribe or broadcast directly.
    public let pubSub: (any PeregrinePubSub)?

    /// The channel registry shared across all `TestApp<App>` instances.
    /// Use `app.channels.broadcast(topic:event:payload:)` to push server-initiated events.
    public let channels: ChannelRegistry

    /// Socket assigns injected into every `ChannelSocket` created via `connectSocket`.
    public let socketAssigns: SocketAssigns

    /// The channel router from the app (for creating `TestChannelSocket` instances).
    private let channelRouter: ChannelRouter

    /// Creates a test harness for the given app type.
    ///
    /// Builds the same pipeline as `main()` but skips server boot.
    ///
    /// - Parameters:
    ///   - type: The `PeregrineApp` type to test.
    ///   - database: Override database config. Pass `.some(nil)` for no DB, or omit to use the app's default.
    ///   - assigns: Socket assigns to inject into every socket created via `connectSocket(_:)`.
    public init(_ type: App.Type, database: Database?? = nil, assigns: SocketAssigns = [:]) async throws {
        let app = App()

        // PubSub setup (call once to get a stable shared instance)
        let pubSubAdapter = app.pubSub
        self.pubSub = pubSubAdapter

        // Channel setup — shared registry per App.Type so cross-instance broadcasts work
        let router = app.channels
        let registry = SharedChannelRegistry.registry(
            for: ObjectIdentifier(App.self),
            router: router
        )
        self.channels = registry
        self.channelRouter = router
        self.socketAssigns = assigns

        // Database setup
        var spectro: SpectroClient?
        let dbConfig = database ?? app.database
        if let dbConfig {
            let client = try SpectroClient(
                hostname: dbConfig.hostname,
                port: dbConfig.port,
                username: dbConfig.username,
                password: dbConfig.password,
                database: dbConfig.database
            )
            spectro = client
            try await app.willStart(spectro: client)
        }

        // Build router
        let httpRouter = Router { app.routes }
        let routerPlug: Plug = { conn in try await httpRouter(conn) }

        // Build pipeline: user plugs → router
        var allPlugs = app.plugs

        // Inject ChannelRegistry into pipeline
        let channelPlug: Plug = { conn in
            conn.assign(ChannelRegistryKey.self, value: registry)
        }
        allPlugs.insert(channelPlug, at: 0)

        if let adapter = pubSubAdapter {
            let pubSubPlug: Plug = { conn in
                conn.assign(PubSubKey.self, value: adapter)
            }
            allPlugs.insert(pubSubPlug, at: 0)
        }

        if let client = spectro {
            let spectroPlug: Plug = { conn in
                conn.assign(SpectroKey.self, value: client)
            }
            allPlugs.insert(spectroPlug, at: 0)
        }

        allPlugs.append(routerPlug)
        self.plug = peregrine_rescueErrors(
            pipeline(allPlugs),
            customErrorPage: app.customErrorPage
        )
    }

    // MARK: - Channel Methods

    /// Creates an in-process channel socket connected to the given path.
    ///
    /// The socket is pre-loaded with the `assigns` provided at `TestApp` init time.
    /// Use the returned `TestChannelSocket` to join topics, push events, and receive broadcasts.
    public func connectSocket(_ path: String) async throws -> TestChannelSocket {
        let socket = ChannelSocket(assigns: socketAssigns, registry: channels)
        return TestChannelSocket(socket: socket, registry: channels, router: channelRouter)
    }

    // MARK: - Request Methods

    /// Sends a GET request through the pipeline.
    public func get(
        _ path: String,
        headers: [String: String] = [:],
        assigns: [String: any Sendable] = [:],
        session: [String: String]? = nil
    ) async throws -> TestResponse {
        try await request(method: .get, path: path, headers: headers, assigns: assigns, session: session)
    }

    /// Sends a POST request with a JSON body through the pipeline.
    public func post(
        _ path: String,
        json: any Encodable & Sendable,
        headers: [String: String] = [:],
        assigns: [String: any Sendable] = [:],
        session: [String: String]? = nil
    ) async throws -> TestResponse {
        let data = try JSONEncoder().encode(json)
        var h = headers
        h["Content-Type"] = "application/json"
        return try await request(method: .post, path: path, body: data, headers: h, assigns: assigns, session: session)
    }

    /// Sends a PUT request with a JSON body through the pipeline.
    public func put(
        _ path: String,
        json: any Encodable & Sendable,
        headers: [String: String] = [:],
        assigns: [String: any Sendable] = [:],
        session: [String: String]? = nil
    ) async throws -> TestResponse {
        let data = try JSONEncoder().encode(json)
        var h = headers
        h["Content-Type"] = "application/json"
        return try await request(method: .put, path: path, body: data, headers: h, assigns: assigns, session: session)
    }

    /// Sends a DELETE request through the pipeline.
    public func delete(
        _ path: String,
        headers: [String: String] = [:],
        assigns: [String: any Sendable] = [:],
        session: [String: String]? = nil
    ) async throws -> TestResponse {
        try await request(method: .delete, path: path, headers: headers, assigns: assigns, session: session)
    }

    /// Sends a request with the given method through the pipeline.
    public func request(
        method: HTTPRequest.Method,
        path: String,
        body: Data? = nil,
        headers: [String: String] = [:],
        assigns: [String: any Sendable] = [:],
        session: [String: String]? = nil
    ) async throws -> TestResponse {
        var fields = HTTPFields()
        for (key, value) in headers {
            if let name = HTTPField.Name(key) {
                fields[name] = value
            }
        }

        let requestBody: RequestBody = body.map { .buffered($0) } ?? .empty

        var conn = TestConnection.build(
            method: method,
            path: path,
            body: requestBody,
            headers: fields
        )

        // Inject assigns
        for (key, value) in assigns {
            conn = conn.assign(key: key, value: value)
        }

        // Inject session
        if let session {
            conn = conn.assign(key: Connection.sessionKey, value: session)
        }

        // Run pipeline
        var result = try await plug(conn)
        result = result.runBeforeSend()

        // Extract response
        let responseData: Data
        switch result.responseBody {
        case .empty:
            responseData = Data()
        case .buffered(let data):
            responseData = data
        case .stream:
            responseData = Data()
        }

        return TestResponse(
            status: result.response.status,
            headers: result.response.headerFields,
            body: responseData
        )
    }
}
