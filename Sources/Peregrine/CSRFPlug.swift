import Foundation
import HTTPTypes
import Nexus

/// Peregrine's CSRF protection plug wrapping Nexus's ``csrfProtection(_:)``.
///
/// Adds Peregrine-specific features on top of Nexus's core CSRF validation:
///
/// - **JSON request skipping** — API requests with `Content-Type: application/json`
///   bypass CSRF checks. APIs typically use bearer tokens, not cookies.
/// - **Path exclusions** — The `except` parameter lists paths that skip validation
///   entirely (e.g., webhook endpoints).
/// - **Template assigns** — Injects `csrfToken` (the raw token string) and
///   `csrfTag` (a ready-to-use `<input type="hidden">` element) into
///   ``Connection/assigns`` for use in templates.
///
/// Requires ``sessionPlug(_:)`` to be earlier in the pipeline.
///
/// ```swift
/// var plugs: [Plug] {
///     [
///         sessionPlug(SessionConfig(secret: mySecret)),
///         peregrine_csrfProtection(except: ["/webhooks/stripe"]),
///         // ...
///     ]
/// }
/// ```
///
/// In your ESW template:
/// ```html
/// <form method="post" action="/submit">
///   <%= csrfTag %>
///   <input type="text" name="title">
///   <button>Submit</button>
/// </form>
/// ```
///
/// - Parameter except: Paths to skip CSRF validation for (exact match).
/// - Returns: A plug that enforces CSRF protection with Peregrine conventions.
public func peregrine_csrfProtection(
    except: [String] = []
) -> Plug {
    let config = CSRFConfig()
    let nexusCSRF = csrfProtection(config)
    let exceptSet = Set(except)

    return { conn in
        let path = conn.request.path ?? "/"

        // Skip excluded paths
        if exceptSet.contains(path) {
            return injectCSRFAssigns(conn: conn, config: config)
        }

        // Skip JSON API requests — they use bearer tokens, not cookies
        if let contentType = conn.getReqHeader(.contentType),
           contentType.contains("application/json") {
            return conn
        }

        // Run Nexus CSRF validation
        let result = try await nexusCSRF(conn)

        // If halted (e.g. 403 Forbidden), return as-is
        guard !result.isHalted else {
            return result
        }

        // Inject csrfToken and csrfTag into assigns for templates
        return injectCSRFAssigns(conn: result, config: config)
    }
}

/// Generates or retrieves the CSRF token and injects it (along with an
/// HTML hidden input tag) into the connection's assigns.
private func injectCSRFAssigns(
    conn: Connection,
    config: CSRFConfig
) -> Connection {
    let (token, updated) = csrfToken(conn: conn, config: config)
    let tag = """
        <input type="hidden" name="\(config.formParam)" value="\(token)">
        """
    return updated
        .assign(key: "csrfToken", value: token)
        .assign(key: "csrfTag", value: tag)
}
