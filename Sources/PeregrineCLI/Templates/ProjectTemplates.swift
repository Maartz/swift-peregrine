import Foundation

enum ProjectTemplates {

    // MARK: - Package.swift

    static func packageSwift(appName: String, includeDB: Bool, includeESW: Bool) -> String {
        let deps = """
                .package(url: "https://github.com/Maartz/swift-peregrine", from: "0.1.0"),
        """

        let targetDeps = """
                    .product(name: "Peregrine", package: "swift-peregrine"),
        """

        let testDeps = """
                    .product(name: "PeregrineTest", package: "swift-peregrine"),
        """

        // These are always pulled in transitively via Peregrine, but
        // we keep the dependency list clean for the consumer.
        _ = (deps, targetDeps, testDeps)

        return """
        // swift-tools-version: 6.0

        import PackageDescription

        let package = Package(
            name: "\(appName)",
            platforms: [
                .macOS(.v14),
            ],
            dependencies: [
        \(deps)
            ],
            targets: [
                .executableTarget(
                    name: "\(appName)",
                    dependencies: [
        \(targetDeps)
                    ]
                ),
                .testTarget(
                    name: "\(appName)Tests",
                    dependencies: [
                        "\(appName)",
        \(testDeps)
                    ]
                ),
            ]
        )
        """
    }

    // MARK: - App.swift

    static func appSwift(appName: String, includeDB: Bool) -> String {
        let dbName = appName
            .replacing(#/([a-z])([A-Z])/#) { "\($0.output.1)_\($0.output.2)" }
            .lowercased()

        let dbLine = includeDB
            ? "\n    let database = Database.postgres(database: \"\(dbName)\")\n"
            : ""

        return """
        import Peregrine

        @main
        struct \(appName): PeregrineApp {\(dbLine)
            @RouteBuilder var routes: [Route] {
                GET("/") { conn in
                    return try conn.json(value: ["message": "Welcome to \(appName)"])
                }
            }
        }
        """
    }

    // MARK: - layout.esw

    static func layoutESW(appName: String) -> String {
        """
        <%!
        var conn: Connection
        var title: String
        var content: String
        %>
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title><%= title %> — \(appName)</title>
        </head>
        <body>
            <%- content %>
        </body>
        </html>
        """
    }

    // MARK: - .gitignore

    static let gitignore = """
    .DS_Store
    .build/
    .swiftpm/
    Package.resolved
    *.xcodeproj
    xcuserdata/
    DerivedData/
    """

    // MARK: - .swift-format

    static let swiftFormat = """
    {
      "version": 1,
      "lineLength": 120,
      "indentation": {
        "spaces": 4
      },
      "respectsExistingLineBreaks": true,
      "lineBreakBeforeControlFlowKeywords": false,
      "lineBreakBeforeEachArgument": true,
      "lineBreakBeforeEachGenericRequirement": false,
      "prioritizeKeepingFunctionOutputTogether": true,
      "indentConditionalCompilationBlocks": true,
      "indentSwitchCaseLabels": false,
      "fileScopedDeclarationPrivacy": {
        "accessLevel": "private"
      },
      "multiElementCollectionTrailingCommas": true
    }
    """
}
