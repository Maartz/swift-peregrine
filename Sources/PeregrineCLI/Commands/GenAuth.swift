import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenAuth: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Generate a complete authentication system (User, UserToken, AuthRoutes, requireAuth)"
    )

    func run() async throws {
        let context = try resolveProject()

        // Generate User model
        try FileCreator.create(
            at: "Sources/\(context.appName)/Models/User.swift",
            in: context.root,
            content: AuthTemplates.userModel()
        )

        // Generate UserToken model
        try FileCreator.create(
            at: "Sources/\(context.appName)/Models/UserToken.swift",
            in: context.root,
            content: AuthTemplates.userTokenModel()
        )

        // Generate AuthRoutes
        try FileCreator.create(
            at: "Sources/\(context.appName)/Routes/AuthRoutes.swift",
            in: context.root,
            content: AuthTemplates.authRoutes()
        )

        // Generate RequireAuth plug
        try FileCreator.create(
            at: "Sources/\(context.appName)/Plugs/RequireAuth.swift",
            in: context.root,
            content: AuthTemplates.requireAuthPlug()
        )

        // Generate Auth helper
        try FileCreator.create(
            at: "Sources/\(context.appName)/Auth.swift",
            in: context.root,
            content: AuthTemplates.authHelper()
        )

        // Generate migrations
        try FileCreator.create(
            at: "Sources/Migrations/\(AuthTemplates.migrationFilename(table: "users"))",
            in: context.root,
            content: AuthTemplates.createUserTableMigration()
        )

        try FileCreator.create(
            at: "Sources/Migrations/\(AuthTemplates.migrationFilename(table: "user_tokens"))",
            in: context.root,
            content: AuthTemplates.createUserTokensTableMigration()
        )

        // Generate auth templates directory
        let viewsPath = "Sources/\(context.appName)/Views/auth"
        let viewsDir = (context.root as NSString).appendingPathComponent(viewsPath)
        try FileManager.default.createDirectory(
            atPath: viewsDir,
            withIntermediateDirectories: true
        )

        // Generate login template
        try FileCreator.create(
            at: "\(viewsPath)/login.esw",
            in: context.root,
            content: AuthTemplates.loginTemplate()
        )

        // Generate register template
        try FileCreator.create(
            at: "\(viewsPath)/register.esw",
            in: context.root,
            content: AuthTemplates.registerTemplate()
        )

        PeregrineUI.noora.success(.alert("Authentication system generated!"))
        PeregrineUI.noora.info(.alert("Run `peregrine migrate up` to create the database tables."))
    }
}
