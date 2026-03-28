import Foundation
@preconcurrency import Noora

enum FileCreator {
    /// Creates a file at the given path relative to `baseDir`, logging with Noora.
    static func create(
        at relativePath: String,
        in baseDir: String,
        content: String
    ) throws {
        let fullPath = (baseDir as NSString).appendingPathComponent(relativePath)
        let dir = (fullPath as NSString).deletingLastPathComponent

        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        try content.write(toFile: fullPath, atomically: true, encoding: .utf8)

        PeregrineUI.noora.success(.alert("create  \(.muted(relativePath))"))
    }
}
