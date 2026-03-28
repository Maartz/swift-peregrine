import Foundation

/// A parsed field from `name:type:modifier` CLI syntax.
struct ParsedField {
    let name: String
    let type: FieldType
    let isOptional: Bool
    let isReference: Bool

    /// The Swift property name in camelCase.
    var swiftName: String {
        toCamelCase(name)
    }

    /// The database column name in snake_case.
    var columnName: String {
        toSnakeCase(name)
    }

    /// The Swift type string (e.g. "String", "UUID?").
    var swiftType: String {
        let base = type.swiftType
        return isOptional ? "\(base)?" : base
    }

    /// The Postgres column type (e.g. "TEXT", "UUID").
    var postgresType: String {
        type.postgresType
    }

    /// The Spectro property wrapper to use.
    var wrapper: String {
        if isReference { return "@ForeignKey" }
        return "@Column"
    }

    /// The SQL column definition.
    var sqlDefinition: String {
        var parts = ["\"\(columnName)\" \(postgresType)"]
        if !isOptional {
            parts.append("NOT NULL")
        }
        if let defaultValue = type.defaultValue, !isOptional {
            parts.append("DEFAULT \(defaultValue)")
        }
        if isReference {
            // category_id → references "categories"("id")
            let baseName = String(columnName.dropLast(3))  // strip _id
            let refTable = pluralize(baseName)
            parts.append("REFERENCES \"\(refTable)\"(\"id\")")
        }
        return parts.joined(separator: " ")
    }
}

/// Supported CLI field types.
enum FieldType: String {
    case string
    case int
    case double
    case bool
    case uuid
    case date

    var swiftType: String {
        switch self {
        case .string: "String"
        case .int: "Int"
        case .double: "Double"
        case .bool: "Bool"
        case .uuid: "UUID"
        case .date: "Date"
        }
    }

    var postgresType: String {
        switch self {
        case .string: "TEXT"
        case .int: "INT"
        case .double: "DOUBLE PRECISION"
        case .bool: "BOOLEAN"
        case .uuid: "UUID"
        case .date: "TIMESTAMPTZ"
        }
    }

    var defaultValue: String? {
        switch self {
        case .string: nil
        case .int: "0"
        case .double: "0"
        case .bool: "true"
        case .uuid: nil
        case .date: nil
        }
    }
}

/// Parses `name:type` and `name:type:modifier` field strings.
///
///     parseFields(["name:string", "price:double", "category_id:uuid:references"])
///
enum FieldParser {
    static func parse(_ args: [String]) throws -> [ParsedField] {
        try args.map { arg in
            let parts = arg.split(separator: ":", maxSplits: 3).map(String.init)
            guard parts.count >= 2 else {
                throw FieldParserError.invalidFormat(arg)
            }
            let name = parts[0]
            guard let type = FieldType(rawValue: parts[1]) else {
                throw FieldParserError.unknownType(parts[1])
            }
            let modifiers = Set(parts.dropFirst(2))
            return ParsedField(
                name: name,
                type: type,
                isOptional: modifiers.contains("optional"),
                isReference: modifiers.contains("references")
            )
        }
    }
}

enum FieldParserError: Error, CustomStringConvertible {
    case invalidFormat(String)
    case unknownType(String)

    var description: String {
        switch self {
        case .invalidFormat(let s):
            "Invalid field format '\(s)'. Expected name:type (e.g. name:string)"
        case .unknownType(let t):
            "Unknown type '\(t)'. Valid types: string, int, double, bool, uuid, date"
        }
    }
}

// MARK: - String Helpers

/// Converts "category_id" or "categoryId" to "categoryId".
func toCamelCase(_ input: String) -> String {
    let parts = input.split(separator: "_")
    guard let first = parts.first else { return input }
    return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
}

/// Converts "categoryId" or "category_id" to "category_id".
func toSnakeCase(_ input: String) -> String {
    if input.contains("_") { return input }
    return input
        .replacing(#/([a-z])([A-Z])/#) { "\($0.output.1)_\($0.output.2)" }
        .lowercased()
}

/// Simple English pluralization.
func pluralize(_ word: String) -> String {
    if word.hasSuffix("s") || word.hasSuffix("x") || word.hasSuffix("ch") || word.hasSuffix("sh") {
        return word + "es"
    }
    if word.hasSuffix("y") && !word.hasSuffix("ay") && !word.hasSuffix("ey") && !word.hasSuffix("oy") && !word.hasSuffix("uy") {
        return String(word.dropLast()) + "ies"
    }
    return word + "s"
}

/// Converts "DonutShop" to "donut_shop".
func toSnakeCaseFromPascal(_ input: String) -> String {
    input
        .replacing(#/([a-z])([A-Z])/#) { "\($0.output.1)_\($0.output.2)" }
        .lowercased()
}
