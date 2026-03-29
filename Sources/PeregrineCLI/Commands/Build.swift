import ArgumentParser
import Foundation
@preconcurrency import Noora

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the Peregrine project (compiles Tailwind CSS if configured, then runs swift build)"
    )

    @Flag(name: .long, help: "Watch for file changes and rebuild automatically")
    var watch: Bool = false

    @Option(name: .long, help: "Port to run the server on (watch mode only)")
    var port: Int?

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath

        if watch {
            try await runWatchMode(cwd: cwd)
        } else {
            try await runBuild(cwd: cwd)
        }
    }

    // MARK: - Standard Build

    private func runBuild(cwd: String) async throws {
        let tailwindBinary = (cwd as NSString).appendingPathComponent(".build/tailwindcss")
        let tailwindConfig = (cwd as NSString).appendingPathComponent("tailwind.config.js")
        let fm = FileManager.default

        // If Tailwind is configured, compile CSS first
        if fm.fileExists(atPath: tailwindBinary) && fm.fileExists(atPath: tailwindConfig) {
            PeregrineUI.noora.info(.alert("Compiling Tailwind CSS..."))

            let tailwindProcess = Process()
            tailwindProcess.executableURL = URL(fileURLWithPath: tailwindBinary)
            tailwindProcess.arguments = [
                "-i", "Public/css/input.css",
                "-o", "Public/css/app.css",
                "--minify",
            ]
            tailwindProcess.currentDirectoryURL = URL(fileURLWithPath: cwd)

            try tailwindProcess.run()
            tailwindProcess.waitUntilExit()

            guard tailwindProcess.terminationStatus == 0 else {
                PeregrineUI.noora.error(.alert(
                    "Tailwind CSS compilation failed.",
                    takeaways: ["Check your tailwind.config.js and input.css for errors."]
                ))
                throw ExitCode.failure
            }

            PeregrineUI.noora.success(.alert("Tailwind CSS compiled"))
        }

        // Run swift build
        PeregrineUI.noora.info(.alert("Running \(.command("swift build"))..."))

        let buildProcess = Process()
        buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        buildProcess.arguments = ["swift", "build"]
        buildProcess.currentDirectoryURL = URL(fileURLWithPath: cwd)

        try buildProcess.run()
        buildProcess.waitUntilExit()

        guard buildProcess.terminationStatus == 0 else {
            PeregrineUI.noora.error(.alert(
                "swift build failed.",
                takeaways: ["Check the compiler output above for errors."]
            ))
            throw ExitCode.failure
        }

        PeregrineUI.noora.success(.alert("Build succeeded"))
    }

    // MARK: - Watch Mode

    private func runWatchMode(cwd: String) async throws {
        guard let root = ProjectDiscovery.findRoot(from: cwd),
              let appName = ProjectDiscovery.findAppName(in: root)
        else {
            PeregrineUI.noora.error(.alert("Could not find Peregrine project"))
            throw ExitCode.failure
        }

        let binaryPath = (cwd as NSString).appendingPathComponent(".build/debug/\(appName)")
        let processManager = ProcessManager()

        // Handle Ctrl+C cleanly via DispatchSource
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            print("")
            print("[peregrine] Shutting down...")
            processManager.stopAll()
            Foundation.exit(0)
        }
        sigintSource.resume()

        // Initial build
        print("[peregrine] Building...")
        let startTime = CFAbsoluteTimeGetCurrent()
        let success = runBuildSync(cwd: cwd)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        if success {
            print("[peregrine] Build complete. (\(String(format: "%.1f", duration))s)")

            // Start Tailwind watch if configured
            let tailwindBinary = (cwd as NSString).appendingPathComponent(".build/tailwindcss")
            let tailwindConfig = (cwd as NSString).appendingPathComponent("tailwind.config.js")
            if FileManager.default.fileExists(atPath: tailwindBinary)
                && FileManager.default.fileExists(atPath: tailwindConfig)
            {
                processManager.startTailwind(binary: tailwindBinary, cwd: cwd)
            }

            // Start server
            processManager.startServer(binary: binaryPath, port: port)
            print("[peregrine] Server started on http://127.0.0.1:\(port ?? 8080)")
        } else {
            print("[peregrine] Build failed. Watching for changes to retry...")
        }

        // Watch for changes
        let sourcesDir = (cwd as NSString).appendingPathComponent("Sources")
        print("[peregrine] Watching for changes...")

        let watcher = FileWatcher(
            paths: [sourcesDir],
            extensions: ["swift", "esw"],
            debounceInterval: 0.3
        ) { changedFiles in
            for file in changedFiles {
                let relative = file.replacingOccurrences(of: cwd + "/", with: "")
                print("[peregrine] Changed: \(relative)")
            }

            print("[peregrine] Rebuilding...")
            let rebuildStart = CFAbsoluteTimeGetCurrent()

            processManager.stopServer()

            let rebuildSuccess = self.runBuildSync(cwd: cwd)
            let rebuildDuration = CFAbsoluteTimeGetCurrent() - rebuildStart

            if rebuildSuccess {
                print("[peregrine] Build complete. (\(String(format: "%.1f", rebuildDuration))s)")
                processManager.startServer(binary: binaryPath, port: self.port)
                print("[peregrine] Server restarted.")
            } else {
                print("[peregrine] Build failed. Fix the error and save to retry.")
            }
        }

        watcher.start() // Blocks until process exits
    }

    // MARK: - Synchronous Build Helper

    private func runBuildSync(cwd: String) -> Bool {
        let tailwindBinary = (cwd as NSString).appendingPathComponent(".build/tailwindcss")
        let tailwindConfig = (cwd as NSString).appendingPathComponent("tailwind.config.js")

        // Tailwind compilation if configured
        if FileManager.default.fileExists(atPath: tailwindBinary)
            && FileManager.default.fileExists(atPath: tailwindConfig)
        {
            let tw = Process()
            tw.executableURL = URL(fileURLWithPath: tailwindBinary)
            tw.arguments = ["-i", "Public/css/input.css", "-o", "Public/css/app.css", "--minify"]
            tw.currentDirectoryURL = URL(fileURLWithPath: cwd)
            do {
                try tw.run()
                tw.waitUntilExit()
                if tw.terminationStatus != 0 { return false }
            } catch {
                return false
            }
        }

        // Swift build
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        build.arguments = ["swift", "build"]
        build.currentDirectoryURL = URL(fileURLWithPath: cwd)
        do {
            try build.run()
            build.waitUntilExit()
            return build.terminationStatus == 0
        } catch {
            return false
        }
    }
}
