import Foundation

/// Server binding configuration.
public struct ServerConfig: Sendable {
    public let host: String
    public let port: Int

    public init(host: String = "127.0.0.1", port: Int = 8080) {
        self.host = host
        self.port = port
    }

    /// Reads `PEREGRINE_HOST` and `PEREGRINE_PORT` from the environment,
    /// falling back to the provided defaults.
    public static func fromEnvironment(
        defaultHost: String = "127.0.0.1",
        defaultPort: Int = 8080
    ) -> ServerConfig {
        let host = ProcessInfo.processInfo.environment["PEREGRINE_HOST"] ?? defaultHost
        let port = ProcessInfo.processInfo.environment["PEREGRINE_PORT"]
            .flatMap(Int.init) ?? defaultPort
        return ServerConfig(host: host, port: port)
    }
}
