import Foundation
import HTTPTypes
import Nexus
import NexusRouter
import os

private let logger = Logger(subsystem: "peregrine", category: "error")

/// A custom error page renderer.
///
/// Return a `Connection` to use your custom page, or `nil` to fall back
/// to Peregrine's default error page for the current environment.
public typealias ErrorPageRenderer = @Sendable (
    _ conn: Connection,
    _ status: Int,
    _ message: String
) -> Connection?

/// Wraps a plug pipeline with environment-aware error handling.
///
/// Compared to Nexus's basic `rescueErrors`:
/// - Content negotiation: JSON for API clients, HTML for browsers
/// - Environment-aware: full detail in dev, generic in prod
/// - Infrastructure error logging: always logs full error server-side
/// - Custom error page support via optional renderer
///
/// - Parameters:
///   - plug: The plug pipeline to wrap.
///   - customErrorPage: Optional custom error page renderer.
/// - Returns: A plug that catches errors and responds appropriately.
public func peregrine_rescueErrors(
    _ plug: @escaping Plug,
    customErrorPage: ErrorPageRenderer? = nil
) -> Plug {
    { conn in
        do {
            return try await plug(conn)
        } catch let error as NexusHTTPError {
            let statusCode = Int(error.status.code)
            let message = error.message.isEmpty
                ? reasonPhrase(for: statusCode)
                : error.message

            return renderError(
                conn: conn,
                status: error.status,
                statusCode: statusCode,
                errorType: "NexusHTTPError",
                message: message,
                customErrorPage: customErrorPage
            )
        } catch {
            // Infrastructure error — always log full detail server-side
            logger.error("Internal error: \(error)")

            let statusCode = 500
            let clientMessage: String
            let errorType: String

            switch Peregrine.env {
            case .dev:
                clientMessage = String(describing: error)
                errorType = String(describing: type(of: error))
            case .test, .prod:
                clientMessage = "Internal Server Error"
                errorType = "Error"
            }

            return renderError(
                conn: conn,
                status: .internalServerError,
                statusCode: statusCode,
                errorType: errorType,
                message: clientMessage,
                customErrorPage: customErrorPage
            )
        }
    }
}

// MARK: - Private

private func renderError(
    conn: Connection,
    status: HTTPResponse.Status,
    statusCode: Int,
    errorType: String,
    message: String,
    customErrorPage: ErrorPageRenderer?
) -> Connection {
    // Try custom error page first
    if let custom = customErrorPage,
       let result = custom(conn, statusCode, message) {
        return result
    }

    if conn.prefersHTML {
        return renderHTMLError(
            conn: conn,
            status: status,
            statusCode: statusCode,
            errorType: errorType,
            message: message
        )
    } else {
        return renderJSONError(
            conn: conn,
            status: status,
            statusCode: statusCode,
            errorType: errorType,
            message: message
        )
    }
}

private func renderHTMLError(
    conn: Connection,
    status: HTTPResponse.Status,
    statusCode: Int,
    errorType: String,
    message: String
) -> Connection {
    let body: String
    switch Peregrine.env {
    case .dev:
        body = devErrorPageHTML(
            status: statusCode,
            errorType: errorType,
            message: message,
            conn: conn
        )
    case .test, .prod:
        body = prodErrorPageHTML(
            status: statusCode,
            reason: reasonPhrase(for: statusCode)
        )
    }
    return conn.html(body, status: status)
}

private func renderJSONError(
    conn: Connection,
    status: HTTPResponse.Status,
    statusCode: Int,
    errorType: String,
    message: String
) -> Connection {
    let encoder = JSONEncoder()
    if Peregrine.env == .dev {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    let body: Data
    switch Peregrine.env {
    case .dev:
        let payload: [String: String] = [
            "error": errorType,
            "status": "\(statusCode)",
            "message": message,
        ]
        body = (try? encoder.encode(payload)) ?? Data("{}".utf8)
    case .test, .prod:
        let payload: [String: String] = [
            "error": reasonPhrase(for: statusCode),
            "status": "\(statusCode)",
        ]
        body = (try? encoder.encode(payload)) ?? Data("{}".utf8)
    }

    var copy = conn
    copy.response.status = status
    copy.response.headerFields[.contentType] = "application/json"
    copy.responseBody = .buffered(body)
    copy.isHalted = true
    return copy
}
