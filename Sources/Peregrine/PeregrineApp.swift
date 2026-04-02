import Foundation
import Hummingbird
import Nexus
import NexusHummingbird
import NexusRouter
import Spectro

/// The main application protocol. Conform to this and add `@main` to get
/// a running web server with zero boilerplate.
///
/// Only `routes` is required — everything else has sensible defaults.
public protocol PeregrineApp {
    /// Database configuration. Return `nil` for apps without a database.
    var database: Database? { get }

    /// PubSub adapter. Return `nil` for apps that don't need pub/sub.
    /// Default: `nil`. Override to use `PubSub.inMemory()` or `PubSub.valkey(url:)`.
    var pubSub: (any PeregrinePubSub)? { get }

    /// Middleware pipeline applied to every request.
    /// Default: `[requestId(), requestLogger()]`.
    var plugs: [Plug] { get }

    /// Route definitions.
    @RouteBuilder var routes: [Route] { get }

    /// Server binding configuration.
    /// Default: reads from `PEREGRINE_HOST` / `PEREGRINE_PORT` env vars,
    /// falls back to `127.0.0.1:8080`.
    var server: ServerConfig { get }

    /// Called after database is connected but before the server starts
    /// accepting connections. Use for seed data, cache warming, etc.
    ///
    /// Only called when `database` is non-nil.
    func willStart(spectro: SpectroClient) async throws

    /// Called during startup to allow per-environment configuration.
    func configure(for env: Environment)

    /// Optional custom error page renderer. Return a `Connection` to
    /// render your own page, or `nil` to use Peregrine's default.
    ///
    /// Use this to hook in compiled ESW error templates (e.g. `Views/errors/404.esw`).
    var customErrorPage: ErrorPageRenderer? { get }

    /// Application entry point. A default implementation is provided
    /// that wires everything together and starts the server.
    static func main() async throws

    init()
}

// MARK: - Defaults

extension PeregrineApp {
    public var database: Database? { nil }

    public var pubSub: (any PeregrinePubSub)? { nil }

    public var plugs: [Plug] {
        [requestId(), requestLogger()]
    }

    public var server: ServerConfig {
        ServerConfig.fromEnvironment()
    }

    public func willStart(spectro: SpectroClient) async throws {}

    public func configure(for env: Environment) {}

    public var customErrorPage: ErrorPageRenderer? { nil }
}

// MARK: - Bootstrap

extension PeregrineApp {
    public static func main() async throws {
        let app = Self()
        app.configure(for: Peregrine.env)

        // PubSub setup (call once to get a stable shared instance)
        let pubSubAdapter = app.pubSub

        // Database setup
        var spectro: SpectroClient?
        if let dbConfig = app.database {
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
        let router = Router { app.routes }
        let routerPlug: Plug = { conn in try await router(conn) }

        // Build pipeline: user plugs → rescue(router)
        var allPlugs = app.plugs

        // Inject PubSub into pipeline if configured
        if let adapter = pubSubAdapter {
            let pubSubPlug: Plug = { conn in
                conn.assign(PubSubKey.self, value: adapter)
            }
            allPlugs.insert(pubSubPlug, at: 0)
        }

        // Inject database into pipeline if configured
        if let client = spectro {
            let spectroPlug: Plug = { conn in
                conn.assign(SpectroKey.self, value: client)
            }
            allPlugs.insert(spectroPlug, at: 0)
        }

        allPlugs.append(routerPlug)
        let finalPlug = peregrine_rescueErrors(
            pipeline(allPlugs),
            customErrorPage: app.customErrorPage
        )

        // Boot server
        let config = app.server
        if Peregrine.env != .test {
            print("Peregrine running on http://\(config.host):\(config.port)")
        }

        let adapter = NexusHummingbirdAdapter(plug: finalPlug)
        let server = Application(
            responder: adapter,
            configuration: .init(address: .hostname(config.host, port: config.port))
        )

        defer {
            if let client = spectro {
                Task { await client.shutdown() }
            }
        }

        try await server.runService()
    }
}
