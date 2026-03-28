import Foundation
import HTTPTypes
import Nexus

extension Connection {

    /// Encodes the given value as JSON and halts, using environment-aware
    /// formatting: pretty-printed in dev, compact otherwise.
    ///
    /// This is a Peregrine-level convenience that wraps Nexus's `json()`
    /// with automatic formatting based on `Peregrine.env`.
    public func jsonPretty<T: Encodable & Sendable>(
        status: HTTPResponse.Status = .ok,
        value: T
    ) throws -> Connection {
        let encoder = JSONEncoder()
        if Peregrine.env == .dev {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try json(status: status, value: value, encoder: encoder)
    }
}
