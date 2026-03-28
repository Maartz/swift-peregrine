import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenHTML: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "html",
        abstract: "Generate a model, migration, routes, and ESW templates"
    )

    @Argument(help: "Model name (e.g. Donut)")
    var name: String

    @Argument(help: "Fields in name:type format (e.g. name:string price:double)")
    var fields: [String] = []

    func run() async throws {
        let context = try resolveProject()
        let parsedFields = try FieldParser.parse(fields)
        let tableName = pluralize(toSnakeCaseFromPascal(name))
        let snakeName = toSnakeCaseFromPascal(name)

        // Generate model
        try FileCreator.create(
            at: "Sources/\(context.appName)/Models/\(name).swift",
            in: context.root,
            content: GeneratorTemplates.model(
                name: name,
                tableName: tableName,
                fields: parsedFields
            )
        )

        // Generate routes
        try FileCreator.create(
            at: "Sources/\(context.appName)/Routes/\(name)Routes.swift",
            in: context.root,
            content: GeneratorTemplates.jsonRoutes(
                name: name,
                fields: parsedFields
            )
        )

        // Generate ESW templates
        try FileCreator.create(
            at: "Sources/\(context.appName)/Views/\(snakeName)_list.esw",
            in: context.root,
            content: GeneratorTemplates.listTemplate(
                name: name,
                fields: parsedFields
            )
        )

        try FileCreator.create(
            at: "Sources/\(context.appName)/Views/\(snakeName)_detail.esw",
            in: context.root,
            content: GeneratorTemplates.detailTemplate(
                name: name,
                fields: parsedFields
            )
        )

        // Generate migration
        let migrationFile = GeneratorTemplates.migrationFilename(tableName: tableName)
        try FileCreator.create(
            at: "Sources/Migrations/\(migrationFile)",
            in: context.root,
            content: GeneratorTemplates.migration(
                tableName: tableName,
                fields: parsedFields
            )
        )
    }
}
