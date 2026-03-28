import Nexus
import Spectro

/// Typed assign key for the SpectroClient in the connection pipeline.
public enum SpectroKey: AssignKey {
    public typealias Value = SpectroClient
}

extension Connection {
    /// The SpectroClient injected by Peregrine's bootstrap.
    /// Available in route handlers when `database` is configured.
    public var spectro: SpectroClient {
        guard let client = self[SpectroKey.self] else {
            fatalError("No database configured. Set `database` in your PeregrineApp.")
        }
        return client
    }

    /// Convenience: creates a fresh repository from the injected SpectroClient.
    public func repo() -> GenericDatabaseRepo {
        spectro.repository()
    }
}
