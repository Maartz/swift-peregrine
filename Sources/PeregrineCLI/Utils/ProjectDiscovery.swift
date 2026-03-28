import Foundation

/// Discovers the Peregrine project structure from the current directory.
enum ProjectDiscovery {

    /// Finds the project root by looking for Package.swift.
    static func findRoot(from dir: String = FileManager.default.currentDirectoryPath) -> String? {
        let packagePath = (dir as NSString).appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packagePath) {
            return dir
        }
        return nil
    }

    /// Extracts the main executable target name from Package.swift.
    static func findAppName(in root: String) -> String? {
        let packagePath = (root as NSString).appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOfFile: packagePath, encoding: .utf8) else {
            return nil
        }

        // Look for .executableTarget(name: "AppName"
        let pattern = #/\.executableTarget\(\s*name:\s*"([^"]+)"/#
        if let match = content.firstMatch(of: pattern) {
            return String(match.output.1)
        }

        // Fallback: look for Sources/<name>/App.swift directories
        let sourcesDir = (root as NSString).appendingPathComponent("Sources")
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: sourcesDir) {
            for entry in entries {
                let appFile = (sourcesDir as NSString)
                    .appendingPathComponent(entry)
                    .appending("/App.swift")
                if FileManager.default.fileExists(atPath: appFile) {
                    return entry
                }
            }
        }

        return nil
    }

    /// Returns the Sources/<AppName> directory path.
    static func sourcesDir(root: String, appName: String) -> String {
        (root as NSString)
            .appendingPathComponent("Sources")
            .appending("/\(appName)")
    }

    /// Returns the Sources/Migrations directory path.
    static func migrationsDir(root: String) -> String {
        (root as NSString)
            .appendingPathComponent("Sources")
            .appending("/Migrations")
    }
}
