import Foundation

enum AuthTemplates {

    // MARK: - User Model

    static func userModel() -> String {
        return """
        import Peregrine

        @Schema("users")
        struct User: Sendable {
            @ID var id: UUID
            @Column var email: String
            @Column var hashedPassword: String
            @Timestamp var createdAt: Date
        }
        """
    }

    // MARK: - UserToken Model

    static func userTokenModel() -> String {
        return """
        import Peregrine

        @Schema("user_tokens")
        struct UserToken: Sendable {
            @ID var id: UUID
            @ForeignKey var userId: UUID
            @Column var token: String
            @Column var context: String
            @Column var sentTo: String?
            @Timestamp var createdAt: Date
        }
        """
    }

    // MARK: - SQL Migrations

    static func createUserTableMigration() -> String {
        return """
        -- migrate:up
        CREATE TABLE "users" (
            "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            "email" TEXT NOT NULL UNIQUE,
            "hashed_password" TEXT NOT NULL,
            "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );

        CREATE UNIQUE INDEX "users_email_index" ON "users" ("email");

        -- migrate:down
        DROP TABLE "users";
        """
    }

    static func createUserTokensTableMigration() -> String {
        return """
        -- migrate:up
        CREATE TABLE "user_tokens" (
            "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
            "token" TEXT NOT NULL,
            "context" TEXT NOT NULL,
            "sent_to" TEXT,
            "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );

        CREATE INDEX "user_tokens_user_id_index" ON "user_tokens" ("user_id");
        CREATE UNIQUE INDEX "user_tokens_token_context_index" ON "user_tokens" ("token", "context");

        -- migrate:down
        DROP TABLE "user_tokens";
        """
    }

    // MARK: - Auth Routes

    static func authRoutes() -> String {
        return """
        import Peregrine
        import Crypto
        import Security

        @RouteBuilder
        func authRoutes() -> [Route] {
            // GET /auth/register — show registration form
            GET("/register") { conn in
                return try conn.render("auth/register", [
                    "error": conn.flash.error as Any,
                    "csrfToken": conn.assigns["csrfToken"] as? String ?? "",
                ])
            }

            // POST /auth/register — create user account
            POST("/register") { conn in
                let email = conn.bodyParams["email"] ?? ""
                let password = conn.bodyParams["password"] ?? ""

                // Validate email
                guard !email.isEmpty, email.contains("@") else {
                    return conn.putFlash(.error, "Please enter a valid email address")
                        .redirect(to: "/auth/register")
                }

                // Validate password length
                guard password.count >= 8 else {
                    return conn.putFlash(.error, "Password must be at least 8 characters")
                        .redirect(to: "/auth/register")
                }

                // Check if email is already taken
                let existing = try await conn.repo().all(User.self)
                if existing.contains(where: { $0.email == email }) {
                    return conn.putFlash(.error, "Email is already taken")
                        .redirect(to: "/auth/register")
                }

                // Hash password and create user
                let hashed = Auth.hashPassword(password)
                var user = User()
                user.email = email
                user.hashedPassword = hashed
                let created = try await conn.repo().insert(user)

                // Generate session token
                let token = Auth.generateToken()
                let tokenHash = Auth.hashToken(token)

                var userToken = UserToken()
                userToken.userId = created.id
                userToken.token = tokenHash
                userToken.context = "session"
                try await conn.repo().insert(userToken)

                // Store token in session and redirect
                return conn
                    .putSession(key: "auth_token", value: token)
                    .putFlash(.info, "Account created successfully!")
                    .redirect(to: "/")
            }

            // GET /auth/login — show login form
            GET("/login") { conn in
                return try conn.render("auth/login", [
                    "error": conn.flash.error as Any,
                    "csrfToken": conn.assigns["csrfToken"] as? String ?? "",
                ])
            }

            // POST /auth/login — authenticate and create session
            POST("/login") { conn in
                let email = conn.bodyParams["email"] ?? ""
                let password = conn.bodyParams["password"] ?? ""

                // Find user by email
                let users = try await conn.repo().all(User.self)
                guard let user = users.first(where: { $0.email == email }) else {
                    return conn.putFlash(.error, "Invalid email or password")
                        .redirect(to: "/auth/login")
                }

                // Verify password
                guard Auth.verifyPassword(password, against: user.hashedPassword) else {
                    return conn.putFlash(.error, "Invalid email or password")
                        .redirect(to: "/auth/login")
                }

                // Generate session token
                let token = Auth.generateToken()
                let tokenHash = Auth.hashToken(token)

                var userToken = UserToken()
                userToken.userId = user.id
                userToken.token = tokenHash
                userToken.context = "session"
                try await conn.repo().insert(userToken)

                // Store token in session and redirect
                return conn
                    .putSession(key: "auth_token", value: token)
                    .putFlash(.info, "Logged in successfully!")
                    .redirect(to: "/")
            }

            // DELETE /auth/logout — clear session and redirect
            DELETE("/logout") { conn in
                if let authToken = conn.getSession("auth_token") {
                    let tokenHash = Auth.hashToken(authToken)
                    // Delete matching session token from database
                    let tokens = try await conn.repo().all(UserToken.self)
                    if let match = tokens.first(where: {
                        $0.token == tokenHash && $0.context == "session"
                    }) {
                        try await conn.repo().delete(UserToken.self, id: match.id)
                    }
                }

                return conn
                    .clearSession()
                    .redirect(to: "/")
            }
        }
        """
    }

    // MARK: - RequireAuth Plug

    static func requireAuthPlug() -> String {
        return """
        import Peregrine
        import Crypto

        /// Returns a plug that requires an authenticated user.
        ///
        /// If the session contains a valid auth token, the matching ``User`` is
        /// loaded from the database and injected into assigns under the key
        /// `"currentUser"`. If no valid token is found, the connection is
        /// redirected to the login page.
        ///
        /// ```swift
        /// // Define once, reuse across multiple scopes:
        /// let adminPipeline = NamedPipeline {
        ///     requireAuth()
        /// }
        ///
        /// scope("/admin", through: adminPipeline) {
        ///     adminRoutes()
        /// }
        /// ```
        ///
        /// - Parameter redirectTo: The path to redirect unauthenticated users to.
        /// - Returns: A plug that enforces authentication.
        func requireAuth(redirectTo: String = "/auth/login") -> Plug {
            { conn in
                guard let authToken = conn.getSession("auth_token") else {
                    return conn.putFlash(.info, "Please log in to continue")
                        .redirect(to: redirectTo)
                }

                let tokenHash = Auth.hashToken(authToken)

                // Look up the session token in the database
                let tokens = try await conn.repo().all(UserToken.self)
                guard let match = tokens.first(where: {
                    $0.token == tokenHash && $0.context == "session"
                }) else {
                    return conn.putFlash(.info, "Please log in to continue")
                        .deleteSession("auth_token")
                        .redirect(to: redirectTo)
                }

                // Load the user
                guard let user = try await conn.repo().get(User.self, id: match.userId) else {
                    return conn.putFlash(.info, "Please log in to continue")
                        .deleteSession("auth_token")
                        .redirect(to: redirectTo)
                }

                // Inject current user into assigns and continue the pipeline
                return conn.assign(key: "currentUser", value: user)
            }
        }
        """
    }

    // MARK: - Auth Helper

    static func authHelper() -> String {
        return """
        import Foundation
        import Crypto
        import Security

        /// Authentication helper functions for password hashing, token
        /// generation, and verification.
        enum Auth {

            /// Hashes a password using SHA-256.
            ///
            /// For production use, consider replacing this with a dedicated
            /// bcrypt library (e.g. swift-bcrypt) for adaptive cost hashing.
            static func hashPassword(_ password: String) -> String {
                var hasher = SHA256()
                hasher.update(data: Data(password.utf8))
                let digest = hasher.finalize()
                return digest.map { String(format: "%02x", $0) }.joined()
            }

            /// Verifies a password against a stored hash.
            static func verifyPassword(_ password: String, against hash: String) -> Bool {
                hashPassword(password) == hash
            }

            /// Hashes a session token for storage in the database.
            ///
            /// Session tokens are stored hashed so that a database leak does
            /// not directly expose valid session credentials.
            static func hashToken(_ token: String) -> String {
                var hasher = SHA256()
                hasher.update(data: Data(token.utf8))
                let digest = hasher.finalize()
                return digest.map { String(format: "%02x", $0) }.joined()
            }

            /// Generates a cryptographically random session token (32 bytes,
            /// base64url-encoded).
            static func generateToken() -> String {
                var bytes = [UInt8](repeating: 0, count: 32)
                _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                return Data(bytes)
                    .base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
        }
        """
    }

    // MARK: - Helpers

    static func migrationFilename(table: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(timestamp)_create_\(table).sql"
    }

    // MARK: - ESW Templates

    static func loginTemplate() -> String {
        return """
        <%!
        var conn: Connection
        var error: String?
        var csrfToken: String
        %>
        <main class="container">
            <article>
                <h1>Log in</h1>
                <% if let error { %>
                <p role="alert" class="error"><%= error %></p>
                <% } %>
                <form method="post" action="/auth/login">
                    <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">
                    <label>
                        Email
                        <input type="email" name="email" required>
                    </label>
                    <label>
                        Password
                        <input type="password" name="password" required>
                    </label>
                    <button type="submit">Log in</button>
                </form>
                <p>Don't have an account? <a href="/auth/register">Register</a></p>
            </article>
        </main>
        """
    }

    static func registerTemplate() -> String {
        return """
        <%!
        var conn: Connection
        var error: String?
        var csrfToken: String
        %>
        <main class="container">
            <article>
                <h1>Register</h1>
                <% if let error { %>
                <p role="alert" class="error"><%= error %></p>
                <% } %>
                <form method="post" action="/auth/register">
                    <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">
                    <label>
                        Email
                        <input type="email" name="email" required>
                    </label>
                    <label>
                        Password
                        <input type="password" name="password" required minlength="8">
                    </label>
                    <button type="submit">Create account</button>
                </form>
                <p>Already have an account? <a href="/auth/login">Log in</a></p>
            </article>
        </main>
        """
    }
}
