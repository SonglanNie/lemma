import Foundation

public enum QuestionProcessEvent: Sendable {
    /// `inputClosed`: the CLI stopped reading before Lemma finished writing the question (it exited, or refused an
    /// option). Lemma stops writing; the exit status and diagnostics that follow say why.
    case output(Data), diagnostic(Data), inputClosed, exited(Int32)
}

/// Pipes are drained off the UI thread, including their final bytes before the exit event.
public final class QuestionProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()

    public init() {
        // A CLI that exits while Lemma is still writing its prompt and images (often more than the 64 KB a pipe
        // buffers) must not end Lemma with SIGPIPE: writes to this pipe fail with EPIPE instead.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    public var isRunning: Bool { process.isRunning }

    public func start(executable: URL, arguments: [String], directory: URL, environment: [String: String], input data: Data? = nil) throws -> AsyncStream<QuestionProcessEvent> {
        process.executableURL = executable; process.arguments = arguments
        process.currentDirectoryURL = directory; process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        // Foundation reports the exit to a handler set before the process starts, so an early exit is never missed;
        // `waitUntilExit` on a worker thread, which polls a run loop, once waited for ever after the CLI had gone.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let (stream, continuation) = AsyncStream<QuestionProcessEvent>.makeStream()
        let group = DispatchGroup()
        for (pipe, diagnostic) in [(output, false), (errors, true)] {
            group.enter()
            let descriptor = pipe.fileHandleForReading.fileDescriptor
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                // read(2) returns whatever has arrived. FileHandle.read(upToCount:) waits for the full count on a pipe,
                // which held back partial answers and a sign-in page's address until the CLI exited.
                var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                while true {
                    let count = read(descriptor, &buffer, buffer.count)
                    if count > 0 {
                        let bytes = Data(buffer[0..<count])
                        continuation.yield(diagnostic ? .diagnostic(bytes) : .output(bytes))
                    } else if count < 0, errno == EINTR {
                        continue
                    } else {
                        break
                    }
                }
            }
        }
        if let data {
            // Not part of the exit group: a write blocked by a stray process holding the pipe must not delay the exit event.
            let handle = input.fileHandleForWriting
            DispatchQueue.global(qos: .utility).async {
                do { try handle.write(contentsOf: data) } catch { continuation.yield(.inputClosed) }
                try? handle.close()
            }
        }
        DispatchQueue.global(qos: .utility).async { [self] in
            exited.wait()
            group.wait()
            continuation.yield(.exited(process.terminationStatus))
            continuation.finish()
        }
        return stream
    }

    /// Sends one line, such as an authorization code. A CLI that has already exited is not an error.
    public func send(_ text: String) { try? input.fileHandleForWriting.write(contentsOf: Data((text + "\n").utf8)) }

    public func cancel() {
        guard process.isRunning else { return }
        process.interrupt()
        let process = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    /// Runs a short command (a status check) and returns its exit code, standard output and standard error.
    /// A command still running after `timeout` is stopped and reported with exit code -1.
    public static func capture(executable: URL, arguments: [String], directory: URL, environment: [String: String],
                               timeout: TimeInterval = 20) async throws -> (code: Int32, output: String, errors: String) {
        let job = QuestionProcess()
        let stream = try job.start(executable: executable, arguments: arguments, directory: directory, environment: environment, input: Data())
        let watchdog = Task { () -> Bool in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return false }
            job.cancel()
            return true
        }
        var output = Data(), errors = Data(), code: Int32 = -1
        for await event in stream {
            switch event {
            case .output(let data): output.append(data)
            case .diagnostic(let data): errors.append(data)
            case .inputClosed: break
            case .exited(let value): code = value
            }
        }
        watchdog.cancel()
        if await watchdog.value { code = -1 }
        return (code, String(decoding: output, as: UTF8.self), String(decoding: errors, as: UTF8.self))
    }
}
