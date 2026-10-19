import Foundation

struct ProcessResult: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data
    /// True when the watchdog stopped the process.
    var timedOut: Bool
}

enum Subprocess {
    /// Runs a program to completion, with stdin from /dev/null, and returns
    /// what it wrote.
    ///
    /// Both pipes are read to the end on their own threads while the program
    /// runs, so output larger than a pipe buffer cannot stall it. After
    /// `timeout`, the program gets SIGTERM and the result says so.
    static func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: Duration
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let (exits, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        try process.run()

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        let readOut = Task.detached { outHandle.readDataToEndOfFile() }
        let readErr = Task.detached { errHandle.readDataToEndOfFile() }

        let pid = process.processIdentifier
        let watchdog = Task.detached { () -> Bool in
            do { try await Task.sleep(for: timeout) } catch { return false }
            kill(pid, SIGTERM)
            return true
        }

        var status: Int32 = -1
        for await code in exits { status = code }
        watchdog.cancel()

        return ProcessResult(
            status: status,
            stdout: await readOut.value,
            stderr: await readErr.value,
            timedOut: await watchdog.value
        )
    }
}
