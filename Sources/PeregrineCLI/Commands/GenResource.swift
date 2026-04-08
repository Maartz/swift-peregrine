import ArgumentParser
import Foundation
@preconcurrency import Noora

struct GenResource: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resource",
        abstract: "Generate a complete CRUD resource (model, context, routes, views, migration)"
    )

    @Argument(help: "Model name in PascalCase (e.g. Post)")
    var name: String

    @Argument(help: "Fields in name:type format (e.g. title:string body:text published:bool)")
    var fields: [String] = []

    @Flag(name: .long, help: "Generate JSON API routes instead of HTML")
    var json = false

    @Flag(name: .long, help: "Generate both HTML and JSON API routes")
    var both = false

    @Flag(name: .long, help: "Generate only model, context, and migration (no routes/views)")
    var modelOnly = false

    @Option(name: .long, help: "Scope foreign key column (e.g. user_id)")
    var scope: String?

    func run() async throws {
        let context = try resolveProject()
        let parsedFields = try FieldParser.parse(fields)
        let tableName = pluralize(toSnakeCaseFromPascal(name))
        let pluralName = pluralize(name)
        let snakeName = toSnakeCaseFromPascal(name)
        let snakePlural = pluralize(snakeName)

        PeregrineUI.noora.info(.alert("Generating resource \(.primary(name))..."))

        // 1. Model
        try FileCreator.create(
            at: "Sources/\(context.appName)/Models/\(name).swift",
            in: context.root,
            content: GeneratorTemplates.model(
                name: name,
                tableName: tableName,
                fields: parsedFields,
                scopeKey: scope
            )
        )

        // 2. Context
        try FileCreator.create(
            at: "Sources/\(context.appName)/Contexts/\(pluralName)Context.swift",
            in: context.root,
            content: GeneratorTemplates.contextTemplate(
                name: name,
                pluralName: pluralName,
                fields: parsedFields,
                scopeKey: scope
            )
        )

        // 3. Routes and views based on variant
        if !modelOnly {
            if json {
                // JSON API only
                try FileCreator.create(
                    at: "Sources/\(context.appName)/Routes/\(pluralName)ApiRoutes.swift",
                    in: context.root,
                    content: GeneratorTemplates.jsonApiRoutes(
                        name: name,
                        pluralName: pluralName,
                        fields: parsedFields
                    )
                )
            } else if both {
                // Both HTML and JSON
                try createHTMLFiles(
                    context: context,
                    name: name,
                    pluralName: pluralName,
                    snakePlural: snakePlural,
                    fields: parsedFields
                )

                try FileCreator.create(
                    at: "Sources/\(context.appName)/Routes/\(pluralName)ApiRoutes.swift",
                    in: context.root,
                    content: GeneratorTemplates.jsonApiRoutes(
                        name: name,
                        pluralName: pluralName,
                        fields: parsedFields
                    )
                )
            } else {
                // HTML (default)
                try createHTMLFiles(
                    context: context,
                    name: name,
                    pluralName: pluralName,
                    snakePlural: snakePlural,
                    fields: parsedFields
                )
            }
        }

        // 4. Migration
        let migrationFile = GeneratorTemplates.migrationFilename(tableName: tableName)
        try FileCreator.create(
            at: "Sources/Migrations/\(migrationFile)",
            in: context.root,
            content: GeneratorTemplates.migration(
                tableName: tableName,
                fields: parsedFields,
                scopeKey: scope
            )
        )

        PeregrineUI.noora.success(.alert(
            "Resource \(.primary(name)) generated.",
            takeaways: [
                "Run 'peregrine migrate' to apply the migration.",
                "Add \(snakePlural)Routes() to your router."
            ]
        ))
    }

    private func createHTMLFiles(
        context: ProjectContext,
        name: String,
        pluralName: String,
        snakePlural: String,
        fields: [ParsedField]
    ) throws {
        // Routes
        try FileCreator.create(
            at: "Sources/\(context.appName)/Routes/\(pluralName)Routes.swift",
            in: context.root,
            content: GeneratorTemplates.htmlRoutes(
                name: name,
                pluralName: pluralName,
                fields: fields
            )
        )

        // Views
        try FileCreator.create(
            at: "Sources/\(context.appName)/Views/\(snakePlural)/index.esw",
            in: context.root,
            content: GeneratorTemplates.listTemplate(
                name: name,
                fields: fields
            )
        )

        try FileCreator.create(
            at: "Sources/\(context.appName)/Views/\(snakePlural)/show.esw",
            in: context.root,
            content: GeneratorTemplates.showTemplate(
                name: name,
                fields: fields
            )
        )

        try FileCreator.create(
            at: "Sources/\(context.appName)/Views/\(snakePlural)/new.esw",
            in: context.root,
            content: GeneratorTemplates.newTemplate(
                name: name,
                fields: fields
            )
        )

        try FileCreator.create(
            at: "Sources/\(context.appName)/Views/\(snakePlural)/edit.esw",
            in: context.root,
            content: GeneratorTemplates.editTemplate(
                name: name,
                fields: fields
            )
        )
    }
}
