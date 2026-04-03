import Foundation

/// TLS configuration for HTTPS termination.
public struct ServerConfig: Sendable {
    public let host: String
    public let port: Int

    /// TLS configuration. When set, the server serves HTTPS and HTTP/2
    /// is automatically enabled via ALPN negotiation.
    public let tls: TLSConfig?

    /// When true, enables HTTP/2. If `tls` is set this flag is redundant
    /// (HTTP/2 auto-enables). Use `http2: true` without TLS for h2c
    /// (cleartext HTTP/2) during local development.
    public let http2: Bool

    /// TLS certificate and key pair.
    public struct TLSConfig: Sendable {
        /// Path to the PEM-encoded certificate file.
        public let certificatePath: String
        /// Path to the PEM-encoded private key file.
        public let keyPath: String

        public init(certificatePath: String, keyPath: String) {
            self.certificatePath = certificatePath
            self.keyPath = keyPath
        }
    }

    // MARK: - Init

    public init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        tls: TLSConfig? = nil,
        http2: Bool = false
    ) {
        self.host = host
        self.port = port
        self.tls = tls
        // If TLS is configured, HTTP/2 is automatically enabled.
        self.http2 = tls != nil ? true : http2
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

    // MARK: - Validation

    /// Validates that any configured TLS certificate and key files exist on
    /// disk. Returns a descriptive error string on failure, or nil if valid.
    public func validate() -> [String]? {
        var errors: [String] = []

        if let tls {
            if !FileManager.default.fileExists(atPath: tls.certificatePath) {
                errors.append("TLS certificate file not found: \(tls.certificatePath)")
            }
            if !FileManager.default.fileExists(atPath: tls.keyPath) {
                errors.append("TLS key file not found: \(tls.keyPath)")
            }
        }

        return errors.isEmpty ? nil : errors
    }
}
