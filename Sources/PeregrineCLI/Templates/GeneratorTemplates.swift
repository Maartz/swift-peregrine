import Foundation

enum GeneratorTemplates {

    // MARK: - Model

    static func model(name: String, tableName: String, fields: [ParsedField], scopeKey: String? = nil) -> String {
        var lines = [
            "import Peregrine",
            "",
            "@Schema(\"\(tableName)\")",
            "struct \(name) {",
            "    @ID var id: UUID",
        ]

        if let scopeKey = scopeKey {
            lines.append("    @ForeignKey var \(toCamelCase(scopeKey)): UUID")
        }

        for field in fields {
            lines.append("    \(field.wrapper) var \(field.swiftName): \(field.swiftType)")
        }

        lines.append("    @Timestamp var createdAt: Date")
        lines.append("    @Timestamp var updatedAt: Date")
        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Migration

    static func migration(tableName: String, fields: [ParsedField], scopeKey: String? = nil) -> String {
        var columns = [
            "    \"id\" UUID PRIMARY KEY DEFAULT gen_random_uuid()",
        ]

        if let scopeKey = scopeKey {
            let snakeKey = toSnakeCase(scopeKey)
            let refTable = pluralize(String(snakeKey.dropLast(3)))  // strip _id
            columns.append("    \"\(snakeKey)\" UUID NOT NULL REFERENCES \"\(refTable)\"(\"id\")")
        }

        for field in fields {
            columns.append("    \(field.sqlDefinition)")
        }

        columns.append("    \"created_at\" TIMESTAMPTZ NOT NULL DEFAULT NOW()")
        columns.append("    \"updated_at\" TIMESTAMPTZ NOT NULL DEFAULT NOW()")

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

    // MARK: - Empty Migration

    static func emptyMigration(description: String) -> String {
        let date = DateFormatter.migrationDate.string(from: Date())
        return """
        -- Migration: \(description)
        -- Created: \(date)

        -- migrate:up
        BEGIN;

        -- TODO: Add your migration SQL here

        COMMIT;

        -- migrate:down
        BEGIN;

        -- TODO: Add your rollback SQL here

        COMMIT;
        """
    }

    // MARK: - Context (Phoenix-Style)

    static func contextTemplate(name: String, pluralName: String, fields: [ParsedField], scopeKey: String? = nil) -> String {
        let lowerName = toLowerFirst(name)
        let formFields = fields.filter { $0.isFormField }

        let scopeFilter: String
        if let scopeKey = scopeKey {
            let camelKey = toCamelCase(scopeKey)
            scopeFilter = """
                        .where(\\.\(camelKey) == scopeId)
            """
        } else {
            scopeFilter = ""
        }

        let scopeParam = scopeKey != nil ? ", scopeId: UUID" : ""
        let scopeAssign: String
        if let scopeKey = scopeKey {
            let camelKey = toCamelCase(scopeKey)
            scopeAssign = "\n        \(lowerName).\(camelKey) = scopeId"
        } else {
            scopeAssign = ""
        }

        let createAssigns = buildAssignLines(fields: formFields, modelVar: lowerName)
        let inputProps = buildInputProps(fields: formFields)

        return """
        import Peregrine

        /// Phoenix-style context for \(name) CRUD operations.
        struct \(pluralName)Context {
            let conn: Connection

            func list\(pluralName)(\(scopeParam.isEmpty ? "" : scopeParam.trimmingCharacters(in: .init(charactersIn: ", ")))) async throws -> [\(name)] {
                try await conn.repo().all(\(name).self)
        \(scopeFilter)    }

            func get\(name)(id: UUID\(scopeParam)) async throws -> \(name) {
                guard let \(lowerName) = try await conn.repo().get(\(name).self, id: id) else {
                    throw NexusHTTPError(.notFound, message: "\(name) not found")
                }
                return \(lowerName)
            }

            func create\(name)(_ input: Create\(name)Input\(scopeParam)) async throws -> \(name) {
                var \(lowerName) = \(name)()\(scopeAssign)
        \(buildAssignLines(fields: formFields, modelVar: lowerName, sourceVar: "input"))
                return try await conn.repo().insert(\(lowerName))
            }

            func update\(name)(_ \(lowerName): \(name), with input: Create\(name)Input) async throws -> \(name) {
                var updated = \(lowerName)
        \(buildAssignLines(fields: formFields, modelVar: "updated", sourceVar: "input"))
                updated.updatedAt = Date()
                return try await conn.repo().insert(updated)
            }

            func delete\(name)(id: UUID) async throws {
                try await conn.repo().delete(\(name).self, id: id)
            }
        }

        struct Create\(name)Input: Decodable, Sendable {
        \(inputProps)
        }
        """
    }

    // MARK: - JSON API Routes

    static func jsonApiRoutes(name: String, pluralName: String, fields: [ParsedField]) -> String {
        let lowerName = toLowerFirst(name)
        let lowerPlural = toLowerFirst(pluralName)
        let formFields = fields.filter { $0.isFormField }
        let assignLines = buildAssignLines(fields: formFields, modelVar: lowerName, sourceVar: "input")
        let inputProps = buildInputProps(fields: formFields)

        return """
        import Peregrine

        @RouteBuilder
        func \(lowerPlural)ApiRoutes() -> [Route] {
            GET("/api/\(lowerPlural)") { conn in
                let items = try await conn.repo().all(\(name).self)
                return try conn.json(value: items)
            }

            GET("/api/\(lowerPlural)/:id") { conn in
                guard let id = conn.params["id"].flatMap(UUID.init) else {
                    throw NexusHTTPError(.badRequest, message: "Invalid ID")
                }
                guard let item = try await conn.repo().get(\(name).self, id: id) else {
                    throw NexusHTTPError(.notFound, message: "\(name) not found")
                }
                return try conn.json(value: item)
            }

            POST("/api/\(lowerPlural)") { conn in
                let input = try conn.decode(as: Create\(name)Input.self)
                var \(lowerName) = \(name)()
        \(assignLines)
                let created = try await conn.repo().insert(\(lowerName))
                return try conn.json(status: .created, value: created)
            }

            PUT("/api/\(lowerPlural)/:id") { conn in
                guard let id = conn.params["id"].flatMap(UUID.init) else {
                    throw NexusHTTPError(.badRequest, message: "Invalid ID")
                }
                guard var \(lowerName) = try await conn.repo().get(\(name).self, id: id) else {
                    throw NexusHTTPError(.notFound, message: "\(name) not found")
                }
                let input = try conn.decode(as: Create\(name)Input.self)
        \(assignLines)
                \(lowerName).updatedAt = Date()
                let updated = try await conn.repo().insert(\(lowerName))
                return try conn.json(value: updated)
            }

            DELETE("/api/\(lowerPlural)/:id") { conn in
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

    // MARK: - HTML Routes

    static func htmlRoutes(name: String, pluralName: String, fields: [ParsedField]) -> String {
        let lowerName = toLowerFirst(name)
        let lowerPlural = toLowerFirst(pluralName)
        let formFields = fields.filter { $0.isFormField }
        let assignLines = buildAssignLines(fields: formFields, modelVar: lowerName, sourceVar: "input")
        let inputProps = buildInputProps(fields: formFields)

        return """
        import Peregrine

        @RouteBuilder
        func \(lowerPlural)Routes() -> [Route] {
            GET("/\(lowerPlural)") { conn in
                let \(lowerPlural) = try await conn.repo().all(\(name).self)
                return try conn.render("\(lowerPlural)/index", ["\(lowerPlural)": \(lowerPlural)])
            }

            GET("/\(lowerPlural)/new") { conn in
                return try conn.render("\(lowerPlural)/new", [:])
            }

            GET("/\(lowerPlural)/:id") { conn in
                guard let id = conn.params["id"].flatMap(UUID.init) else {
                    throw NexusHTTPError(.badRequest, message: "Invalid ID")
                }
                guard let \(lowerName) = try await conn.repo().get(\(name).self, id: id) else {
                    throw NexusHTTPError(.notFound, message: "\(name) not found")
                }
                return try conn.render("\(lowerPlural)/show", ["\(lowerName)": \(lowerName)])
            }

            POST("/\(lowerPlural)") { conn in
                let input = try conn.decode(as: Create\(name)Input.self)
                var \(lowerName) = \(name)()
        \(assignLines)
                let created = try await conn.repo().insert(\(lowerName))
                return conn.redirect(to: "/\(lowerPlural)/\\(created.id)")
            }

            GET("/\(lowerPlural)/:id/edit") { conn in
                guard let id = conn.params["id"].flatMap(UUID.init) else {
                    throw NexusHTTPError(.badRequest, message: "Invalid ID")
                }
                guard let \(lowerName) = try await conn.repo().get(\(name).self, id: id) else {
                    throw NexusHTTPError(.notFound, message: "\(name) not found")
                }
                return try conn.render("\(lowerPlural)/edit", ["\(lowerName)": \(lowerName)])
            }

            PUT("/\(lowerPlural)/:id") { conn in
                guard let id = conn.params["id"].flatMap(UUID.init) else {
                    throw NexusHTTPError(.badRequest, message: "Invalid ID")
                }
                guard var \(lowerName) = try await conn.repo().get(\(name).self, id: id) else {
                    throw NexusHTTPError(.notFound, message: "\(name) not found")
                }
                let input = try conn.decode(as: Create\(name)Input.self)
        \(assignLines)
                \(lowerName).updatedAt = Date()
                try await conn.repo().insert(\(lowerName))
                return conn.redirect(to: "/\(lowerPlural)/\\(id)")
            }

            DELETE("/\(lowerPlural)/:id") { conn in
                guard let id = conn.params["id"].flatMap(UUID.init) else {
                    throw NexusHTTPError(.badRequest, message: "Invalid ID")
                }
                try await conn.repo().delete(\(name).self, id: id)
                return conn.redirect(to: "/\(lowerPlural)")
            }
        }

        private struct Create\(name)Input: Decodable, Sendable {
        \(inputProps)
        }
        """
    }

    // MARK: - JSON Routes (Legacy)

    static func jsonRoutes(name: String, fields: [ParsedField]) -> String {
        let lowerName = toLowerFirst(name)
        let inputFields = fields.filter { !$0.isReference }
        let inputProps = buildInputProps(fields: inputFields)
        let assignLines = buildAssignLines(fields: inputFields, modelVar: lowerName, sourceVar: "input")

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

    // MARK: - ESW Views: Index (List)

    static func listTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerName = toLowerFirst(name)
        let lowerPlural = pluralize(String(lowerName))

        let headerCells = fields.prefix(3).map { "<th>\($0.swiftName)</th>" }.joined(separator: "\n            ")
        let bodyCells = fields.prefix(3).map { "<td><%= \(lowerName).\($0.swiftName) %></td>" }.joined(separator: "\n            ")

        return """
        <%!
        var conn: Connection
        var \(lowerPlural): [\(name)]
        %>
        <h1>\(name) List</h1>

        <p><a href="/\(lowerPlural)/new">New \(name)</a></p>

        <table>
            <thead>
                <tr>
                \(headerCells)
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
            <% for \(lowerName) in \(lowerPlural) { %>
                <tr>
                \(bodyCells)
                    <td>
                        <a href="/\(lowerPlural)/<%= \(lowerName).id %>">View</a>
                        <a href="/\(lowerPlural)/<%= \(lowerName).id %>/edit">Edit</a>
                    </td>
                </tr>
            <% } %>
            </tbody>
        </table>
        """
    }

    // MARK: - ESW Views: Show (Detail)

    static func showTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerName = toLowerFirst(name)
        let lowerPlural = pluralize(String(lowerName))

        let fieldLines = fields.filter { $0.isFormField }.map { field in
            "<p><strong>\(field.swiftName):</strong> <%= \(lowerName).\(field.swiftName) %></p>"
        }.joined(separator: "\n")

        return """
        <%!
        var conn: Connection
        var \(lowerName): \(name)
        %>
        <h1><%= \(lowerName).\(fields.first?.swiftName ?? "id") %></h1>

        <p><small>Created: <%= \(lowerName).createdAt %></small></p>

        \(fieldLines)

        <p>
            <a href="/\(lowerPlural)">Back</a>
            <a href="/\(lowerPlural)/<%= \(lowerName).id %>/edit">Edit</a>
        </p>

        <form method="post" action="/\(lowerPlural)/<%= \(lowerName).id %>">
            <input type="hidden" name="_method" value="DELETE">
            <button type="submit">Delete</button>
        </form>
        """
    }

    // MARK: - ESW Views: New

    static func newTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerPlural = pluralize(toLowerFirst(name))
        let formFields = fields.filter { $0.isFormField }

        let fieldInputs = formFields.map { field in
            buildFormInput(for: field, modelVar: nil)
        }.joined(separator: "\n\n")

        return """
        <%!
        var conn: Connection
        var csrfToken: String
        %>
        <h1>New \(name)</h1>

        <form method="post" action="/\(lowerPlural)">
            <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">

        \(fieldInputs)

            <button type="submit">Create \(name)</button>
        </form>

        <p><a href="/\(lowerPlural)">Back</a></p>
        """
    }

    // MARK: - ESW Views: Edit

    static func editTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerName = toLowerFirst(name)
        let lowerPlural = pluralize(lowerName)
        let formFields = fields.filter { $0.isFormField }

        let fieldInputs = formFields.map { field in
            buildFormInput(for: field, modelVar: lowerName)
        }.joined(separator: "\n\n")

        return """
        <%!
        var conn: Connection
        var \(lowerName): \(name)
        var csrfToken: String
        %>
        <h1>Edit \(name)</h1>

        <form method="post" action="/\(lowerPlural)/<%= \(lowerName).id %>">
            <input type="hidden" name="_method" value="PUT">
            <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">

        \(fieldInputs)

            <button type="submit">Update \(name)</button>
        </form>

        <p><a href="/\(lowerPlural)/<%= \(lowerName).id %>">Cancel</a></p>
        """
    }

    // MARK: - Legacy Alias

    static func detailTemplate(name: String, fields: [ParsedField]) -> String {
        showTemplate(name: name, fields: fields)
    }

    // MARK: - Filename Helpers

    static func migrationFilename(tableName: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(timestamp)_create_\(tableName).sql"
    }

    static func migrationFilename(description: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let sanitized = description
            .replacing(#/[^a-zA-Z0-9]/#) { _ in "_" }
            .lowercased()
            .replacing(#/__+/#) { _ in "_" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "\(timestamp)_\(sanitized).sql"
    }

    // MARK: - Private Helpers

    /// Generates `modelVar.field = sourceVar.field` assignment lines for template code.
    private static func buildAssignLines(fields: [ParsedField], modelVar: String, sourceVar: String = "input") -> String {
        fields.map { field in
            "        \(modelVar).\(field.swiftName) = \(sourceVar).\(field.swiftName)"
        }.joined(separator: "\n")
    }

    /// Generates `let fieldName: Type` property declarations for input structs.
    private static func buildInputProps(fields: [ParsedField]) -> String {
        fields.map { field in
            "    let \(field.swiftName): \(field.swiftType)"
        }.joined(separator: "\n")
    }

    /// Generates an HTML form input. When `modelVar` is non-nil, pre-populates with existing values.
    private static func buildFormInput(for field: ParsedField, modelVar: String?) -> String {
        let valueAttr: String
        if let mv = modelVar {
            valueAttr = "<%= \(mv).\(field.swiftName) %>"
        } else {
            valueAttr = ""
        }

        if field.isTextarea {
            return """
                <label>
                    \(field.displayName)
                    <textarea name="\(field.swiftName)"\(field.isOptional ? "" : " required")>\(valueAttr)</textarea>
                </label>
            """
        }

        if field.type == .bool {
            let checked = modelVar.map { " <%= \($0).\(field.swiftName) ? \"checked\" : \"\" %>" } ?? ""
            return """
                <label>
                    <input type="checkbox" name="\(field.swiftName)"\(checked)>
                    \(field.displayName)
                </label>
            """
        }

        let step = field.type == .double ? " step=\"any\"" : ""
        let value = modelVar != nil ? " value=\"\(valueAttr)\"" : ""
        return """
            <label>
                \(field.displayName)
                <input type="\(field.htmlInputType)" name="\(field.swiftName)"\(value)\(step)\(field.isOptional ? "" : " required")>
            </label>
        """
    }
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let migrationDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
