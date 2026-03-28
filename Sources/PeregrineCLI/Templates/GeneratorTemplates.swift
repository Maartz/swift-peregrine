import Foundation

enum GeneratorTemplates {

    // MARK: - Model

    static func model(name: String, tableName: String, fields: [ParsedField]) -> String {
        var lines = [
            "import Peregrine",
            "",
            "@Schema(\"\(tableName)\")",
            "struct \(name) {",
            "    @ID var id: UUID",
        ]

        for field in fields {
            lines.append("    \(field.wrapper) var \(field.swiftName): \(field.swiftType)")
        }

        lines.append("    @Timestamp var createdAt: Date")
        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Migration

    static func migration(tableName: String, fields: [ParsedField]) -> String {
        var columns = [
            "    \"id\" UUID PRIMARY KEY DEFAULT gen_random_uuid()",
        ]

        for field in fields {
            columns.append("    \(field.sqlDefinition)")
        }

        columns.append("    \"created_at\" TIMESTAMPTZ NOT NULL DEFAULT NOW()")

        let columnsSQL = columns.joined(separator: ",\n")

        return """
        -- migrate:up
        CREATE TABLE "\(tableName)" (
        \(columnsSQL)
        );

        -- migrate:down
        DROP TABLE "\(tableName)";
        """
    }

    // MARK: - JSON Routes

    static func jsonRoutes(name: String, fields: [ParsedField]) -> String {
        let lowerName = name.prefix(1).lowercased() + name.dropFirst()
        let inputFields = fields.filter { !$0.isReference }

        var inputProps = inputFields.map { field in
            "    let \(field.swiftName): \(field.swiftType)"
        }.joined(separator: "\n")

        var assignLines = inputFields.map { field in
            "        \(lowerName).\(field.swiftName) = input.\(field.swiftName)"
        }.joined(separator: "\n")

        return """
        import Peregrine

        @RouteBuilder
        func \(lowerName)Routes() -> [Route] {
            GET("/") { conn in
                let items = try await conn.repo().all(\(name).self)
                return try conn.json(value: items)
            }

            GET("/:id") { conn in
                guard let id = conn.params["id"].flatMap(UUID.init) else {
                    throw NexusHTTPError(.badRequest, message: "Invalid ID")
                }
                guard let item = try await conn.repo().get(\(name).self, id: id) else {
                    throw NexusHTTPError(.notFound, message: "\(name) not found")
                }
                return try conn.json(value: item)
            }

            POST("/") { conn in
                let input = try conn.decode(as: Create\(name)Input.self)
                var \(lowerName) = \(name)()
        \(assignLines)
                let created = try await conn.repo().insert(\(lowerName))
                return try conn.json(status: .created, value: created)
            }

            DELETE("/:id") { conn in
                guard let id = conn.params["id"].flatMap(UUID.init) else {
                    throw NexusHTTPError(.badRequest, message: "Invalid ID")
                }
                try await conn.repo().delete(\(name).self, id: id)
                return try conn.json(value: ["deleted": true])
            }
        }

        private struct Create\(name)Input: Decodable, Sendable {
        \(inputProps)
        }
        """
    }

    // MARK: - HTML Templates

    static func listTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerName = name.prefix(1).lowercased() + name.dropFirst()
        let lowerPlural = pluralize(String(lowerName))

        var headerCells = fields.prefix(3).map { "<th>\($0.swiftName)</th>" }.joined(separator: "\n            ")
        var bodyCells = fields.prefix(3).map { "<td><%= \(lowerName).\($0.swiftName) %></td>" }.joined(separator: "\n            ")

        return """
        <%!
        var conn: Connection
        var \(lowerPlural): [\(name)]
        %>
        <h1>\(name) List</h1>
        <table>
            <thead>
                <tr>
                \(headerCells)
                </tr>
            </thead>
            <tbody>
            <% for \(lowerName) in \(lowerPlural) { %>
                <tr>
                \(bodyCells)
                </tr>
            <% } %>
            </tbody>
        </table>
        """
    }

    static func detailTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerName = name.prefix(1).lowercased() + name.dropFirst()

        var fieldLines = fields.map { field in
            "<p><strong>\(field.swiftName):</strong> <%= \(lowerName).\(field.swiftName) %></p>"
        }.joined(separator: "\n")

        return """
        <%!
        var conn: Connection
        var \(lowerName): \(name)
        %>
        <h1>\(name) Detail</h1>
        \(fieldLines)
        """
    }

    // MARK: - Helpers

    static func migrationFilename(tableName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = formatter.string(from: Date())
        let pascalTable = tableName.prefix(1).uppercased() + tableName.dropFirst()
        return "\(timestamp)_Create\(pascalTable).sql"
    }
}
