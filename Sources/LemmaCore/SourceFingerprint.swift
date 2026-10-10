import Foundation
import Darwin
import Synchronization

/// What identifies a file's bytes without reading them: its volume and file number, size and modification time.
/// Writing the bytes changes the modification time, and replacing the file (as downloads and syncs do) its number.
public struct FileStamp: Codable, Hashable, Sendable {
    public var device: Int32
    public var inode: UInt64
    public var size: Int64
    /// Nanoseconds since 1970.
    public var modified: Int64

    /// The stamp of a regular file, or nil when there is none at that path.
    public init?(_ url: URL) {
        var info = stat()
        guard stat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        device = info.st_dev; inode = info.st_ino; size = Int64(info.st_size)
        modified = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
    }

    /// The file this stamp describes, whatever its name now (a rename keeps the number).
    var fileKey: String { "\(device):\(inode)" }
}

/// Decoded workspaces by file, kept while the file is unchanged, so the library is not decoded again each time it is
/// listed (three times at launch) and switching to a book decodes no workspace.json that has not changed since it was read.
enum WorkspaceCache {
    private struct Entry: Sendable { let stamp: FileStamp; let workspace: StudyWorkspace }
    private static let entries = Mutex<[String: Entry]>([:])

    static func lookup(_ url: URL, stamp: FileStamp) -> StudyWorkspace? {
        entries.withLock { entries in
            guard let entry = entries[url.path], entry.stamp == stamp else { return nil }
            return entry.workspace
        }
    }

    static func store(_ workspace: StudyWorkspace, url: URL, stamp: FileStamp) {
        entries.withLock { $0[url.path] = Entry(stamp: stamp, workspace: workspace) }
    }

    static func remove(_ url: URL) {
        _ = entries.withLock { $0.removeValue(forKey: url.path) }
    }
}

/// Fingerprints of PDFs already read, kept in the support folder (`Fingerprints.json`), so opening a known file never
/// reads all its bytes again; a file whose stamp changed is read once more.
public final class FingerprintCache: Sendable {
    struct Entry: Codable, Sendable {
        var stamp: FileStamp
        var fingerprint: String
        var used: Date
    }
    private struct Saved: Codable { var version = 1; var entries: [Entry] }
    public let file: URL
    private let writer: WorkspaceWriter
    private let entries: Mutex<[String: Entry]>
    /// Old entries go first beyond this many files.
    static let limit = 4000

    public init(root: URL) {
        file = root.appendingPathComponent("Fingerprints.json")
        writer = WorkspaceWriter.shared(for: root)
        let saved = (try? Data(contentsOf: root.appendingPathComponent("Fingerprints.json")))
            .flatMap { try? WorkspaceRepository.decoder.decode(Saved.self, from: $0) }
        entries = Mutex(Dictionary((saved?.entries ?? []).map { ($0.stamp.fileKey, $0) }, uniquingKeysWith: { first, _ in first }))
    }

    /// The fingerprint of the file with this stamp, if it was read before and has not changed since.
    public func fingerprint(for stamp: FileStamp) -> String? {
        entries.withLock { entries in
            guard var entry = entries[stamp.fileKey], entry.stamp == stamp else { return nil }
            entry.used = .now; entries[stamp.fileKey] = entry
            return entry.fingerprint
        }
    }

    /// Remembers what a file's bytes hash to, and saves the list in the background.
    public func record(_ fingerprint: String, for stamp: FileStamp) {
        let snapshot = entries.withLock { entries -> [Entry] in
            entries[stamp.fileKey] = Entry(stamp: stamp, fingerprint: fingerprint, used: .now)
            if entries.count > Self.limit {
                for (key, _) in entries.sorted(by: { $0.value.used < $1.value.used }).prefix(entries.count - Self.limit) { entries[key] = nil }
            }
            return Array(entries.values)
        }
        let file = file, writer = writer
        writer.enqueue {
            guard let data = try? writer.encode(Saved(entries: snapshot.sorted { $0.used > $1.used })) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// Reads a PDF's fingerprint: at once for a small local file, otherwise off the main thread, through a coordinated read
/// so a file in iCloud Drive or another cloud folder is downloaded (or saved by the app editing it) before it is read.
public enum SourceFingerprint {
    /// Files up to this size are hashed where they are asked for (a few milliseconds); larger ones in the background.
    public static let immediateLimit: Int64 = 4 << 20

    /// Whether reading the whole file could keep the asking thread waiting: large, on a network volume, or in the cloud.
    public static func wantsBackground(_ url: URL, limit: Int64 = immediateLimit) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isUbiquitousItemKey, .volumeIsLocalKey]) else { return true }
        if values.isUbiquitousItem == true || values.volumeIsLocal == false { return true }
        return Int64(values.fileSize ?? .max) > limit
    }

    /// The fingerprint of the file's bytes and the stamp they had, or no stamp when the file changed while it was read.
    public static func read(_ url: URL, coordinated: Bool) throws -> (fingerprint: String, stamp: FileStamp?) {
        var outcome: Result<(String, FileStamp?), Error> = .failure(CocoaError(.fileReadUnknown))
        let hash = { (url: URL) in
            let before = FileStamp(url)
            do {
                let fingerprint = try WorkspaceRepository.fingerprint(of: url)
                let after = FileStamp(url)
                outcome = .success((fingerprint, before != nil && before == after ? after : nil))
            } catch { outcome = .failure(error) }
        }
        if coordinated {
            var coordinationError: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { hash($0) }
            if let coordinationError { throw coordinationError }
        } else { hash(url) }
        let (fingerprint, stamp) = try outcome.get()
        return (fingerprint, stamp)
    }
}
