import ArgumentParser
import Foundation
@preconcurrency import Noora

struct New: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new Peregrine project"
    )

    @Argument(help: "Name of the project (e.g. DonutShop)")
    var appName: String

    @Flag(name: .long, help: "Omit database configuration")
    var noDb = false

    @Flag(name: .long, help: "Omit Views directory and ESW templates")
    var noEsw = false

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        let projectDir = (cwd as NSString).appendingPathComponent(appName)

        guard !FileManager.default.fileExists(atPath: projectDir) else {
            PeregrineUI.noora.error(.alert(
                "Directory \(.primary(appName)) already exists.",
                takeaways: ["Choose a different name or remove the existing directory."]
            ))
            throw ExitCode.failure
        }

        PeregrineUI.noora.info(.alert("Creating \(.primary(appName))..."))

        let includeDB = !noDb
        let includeESW = !noEsw

        // Package.swift
        try FileCreator.create(
            at: "Package.swift",
            in: projectDir,
            content: ProjectTemplates.packageSwift(
                appName: appName,
                includeDB: includeDB,
                includeESW: includeESW
            )
        )

        // App.swift
        try FileCreator.create(
            at: "Sources/\(appName)/App.swift",
            in: projectDir,
            content: ProjectTemplates.appSwift(appName: appName, includeDB: includeDB)
        )

        // Routes/.gitkeep
        try FileCreator.create(
            at: "Sources/\(appName)/Routes/.gitkeep",
            in: projectDir,
            content: ""
        )

        // Models/.gitkeep
        try FileCreator.create(
            at: "Sources/\(appName)/Models/.gitkeep",
            in: projectDir,
            content: ""
        )

        // Views/layout.esw (if ESW enabled)
        if includeESW {
            try FileCreator.create(
                at: "Sources/\(appName)/Views/layout.esw",
                in: projectDir,
                content: ProjectTemplates.layoutESW(appName: appName)
            )
        }

        // Migrations/.gitkeep (if DB enabled)
        if includeDB {
            try FileCreator.create(
                at: "Sources/Migrations/.gitkeep",
                in: projectDir,
                content: ""
            )
        }

        // Tests/.gitkeep
        try FileCreator.create(
            at: "Tests/\(appName)Tests/.gitkeep",
            in: projectDir,
            content: ""
        )

        // .gitignore
        try FileCreator.create(
            at: ".gitignore",
            in: projectDir,
            content: ProjectTemplates.gitignore
        )

        // .swift-format
        try FileCreator.create(
            at: ".swift-format",
            in: projectDir,
            content: ProjectTemplates.swiftFormat
        )

        PeregrineUI.noora.success(.alert(
            "Project \(.primary(appName)) created",
            takeaways: [
                "cd \(.command(appName))",
                "swift run",
            ]
        ))
    }
}
