import Foundation

/// The runtime environment for a Peregrine application.
public enum Environment: String, Sendable {
    case dev
    case test
    case prod
}

/// Top-level Peregrine namespace.
public enum Peregrine {
    /// Current environment, read once at startup from the `PEREGRINE_ENV`
    /// environment variable. Defaults to `.dev` when unset or unrecognized.
    public static let env: Environment = {
        guard let raw = ProcessInfo.processInfo.environment["PEREGRINE_ENV"] else {
            return .dev
        }
        return Environment(rawValue: raw) ?? .dev
    }()
}
