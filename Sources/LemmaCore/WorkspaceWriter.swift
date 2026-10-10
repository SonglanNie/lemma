import Foundation
import Synchronization

/// Writes one support folder's files in order on a single utility queue. Saving a workspace encodes and writes it here,
/// off the main thread: a later snapshot always lands after an earlier one, synchronous saves (closing a book, quitting)
/// wait for everything queued before them, and reads of the folder wait for pending writes, so nothing reads an older file.
public final class WorkspaceWriter: Sendable {
    private let queue: DispatchQueue
    private let key = DispatchSpecificKey<Bool>()
    /// Folders already created, so a save does not ask the file system to create them again. Touched only on the queue.
    nonisolated(unsafe) private var createdFolders: Set<String> = []
    /// Encoders reused across saves; used only on the queue. The library's own files are read by Lemma alone, so they are
    /// written compactly (exports stay pretty-printed for people).
    private let compactEncoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder
    }()
    private let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let writers = Mutex<[String: WorkspaceWriter]>([:])

    /// The writer of a support folder: every repository value for the same folder shares its order.
    public static func shared(for root: URL) -> WorkspaceWriter {
        let path = root.standardizedFileURL.path
        return writers.withLock { writers in
            if let writer = writers[path] { return writer }
            let writer = WorkspaceWriter(label: path)
            writers[path] = writer
            return writer
        }
    }

    private init(label: String) {
        queue = DispatchQueue(label: "Lemma.WorkspaceWriter \(label)", qos: .utility)
        queue.setSpecific(key: key, value: true)
    }

    private var isOnQueue: Bool { DispatchQueue.getSpecific(key: key) == true }

    /// Runs after everything queued so far, without waiting.
    public func enqueue(_ work: @escaping @Sendable () -> Void) { queue.async(execute: work) }

    /// Runs after everything queued so far and waits for it (on the queue already, it simply runs).
    public func sync<T>(_ work: () throws -> T) rethrows -> T {
        if isOnQueue { return try work() }
        return try queue.sync(execute: work)
    }

    /// Returns once every write queued before this call is on disk.
    public func waitUntilIdle() {
        guard !isOnQueue else { return }
        queue.sync {}
    }

    // MARK: On the queue

    /// Encodes compactly (or pretty-printed for files people may read) with the queue's own encoder.
    func encode<T: Encodable>(_ value: T, pretty: Bool = false) throws -> Data {
        dispatchPrecondition(condition: .onQueue(queue))
        return try (pretty ? prettyEncoder : compactEncoder).encode(value)
    }

    /// Creates a folder once per session; later saves into it skip the system call.
    func ensureFolder(_ folder: URL) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !createdFolders.contains(folder.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        createdFolders.insert(folder.path)
    }

    /// A folder removed outside the queue (or by another process) must be created again before the next write.
    func forgetFolder(_ folder: URL) {
        dispatchPrecondition(condition: .onQueue(queue))
        createdFolders.remove(folder.path)
    }
}
