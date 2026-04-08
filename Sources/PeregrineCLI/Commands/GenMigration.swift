import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenMigration: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migration",
        abstract: "Generate an empty migration file"
    )

    @Argument(help: "Migration description in PascalCase (e.g. AddSlugToPosts)")
    var name: String

    func run() async throws {
        let context = try resolveProject()
        let filename = GeneratorTemplates.migrationFilename(description: name)

        try FileCreator.create(
            at: "Sources/Migrations/\(filename)",
            in: context.root,
            content: GeneratorTemplates.emptyMigration(description: name)
        )
    }
}
