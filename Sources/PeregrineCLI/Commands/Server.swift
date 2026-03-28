import ArgumentParser
import Foundation

struct Server: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "server",
        abstract: "Build and run the app"
    )

    @Option(name: .long, help: "Port to run on")
    var port: Int?

    func run() async throws {
        var args = ["swift", "run"]
        if let port {
            args += ["--", "--port", "\(port)"]
        }

        PeregrineUI.noora.info(.alert("Starting server..."))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
    }
}
