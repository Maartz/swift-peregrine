import Foundation

/// Manages child processes for the dev server.
final class ProcessManager: @unchecked Sendable {
    private var serverProcess: Process?
    private var tailwindProcess: Process?

    /// Start the server binary.
    func startServer(binary: String, port: Int?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        if let port {
            process.arguments = ["--port", "\(port)"]
        }

        do {
            try process.run()
            serverProcess = process
        } catch {
            print("[peregrine] Failed to start server: \(error.localizedDescription)")
        }
    }

    /// Stop the server (SIGTERM, wait up to 2s, then SIGKILL).
    func stopServer() {
        guard let process = serverProcess, process.isRunning else {
            serverProcess = nil
            return
        }

        process.terminate()

        let semaphore = DispatchSemaphore(value: 0)
        let workItem = DispatchWorkItem {
            process.waitUntilExit()
            semaphore.signal()
        }
        DispatchQueue.global().async(execute: workItem)

        let result = semaphore.wait(timeout: .now() + 2.0)
        if result == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }

        serverProcess = nil
    }

    /// Start Tailwind in watch mode.
    func startTailwind(binary: String, cwd: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-i", "Public/css/input.css", "-o", "Public/css/app.css", "--watch"]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            tailwindProcess = process
        } catch {
            print("[peregrine] Failed to start Tailwind: \(error.localizedDescription)")
        }
    }

    /// Stop all processes.
    func stopAll() {
        if let tw = tailwindProcess, tw.isRunning {
            tw.terminate()
            tw.waitUntilExit()
            tailwindProcess = nil
        }
        stopServer()
    }
}
