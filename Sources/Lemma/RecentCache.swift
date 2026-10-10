import Foundation
import LemmaCore

/// A small cache that keeps the entries used most recently and drops the least recently used one when full. Sized for
/// a few dozen pages, so the linear bookkeeping costs less than hashing a second structure.
@MainActor
final class RecentCache<Key: Hashable, Value> {
    private var values: [Key: Value] = [:]
    /// Least recently used first.
    private var order: [Key] = []
    let capacity: Int

    init(capacity: Int) { self.capacity = max(1, capacity) }

    func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        if order.last != key, let index = order.lastIndex(of: key) { order.remove(at: index); order.append(key) }
        return value
    }

    func insert(_ value: Value, for key: Key) {
        if values.updateValue(value, forKey: key) == nil { order.append(key) }
        else if let index = order.lastIndex(of: key) { order.remove(at: index); order.append(key) }
        while order.count > capacity { values[order.removeFirst()] = nil }
    }

    /// The cached value, or the one `make` computes (then kept).
    func value(for key: Key, make: () -> Value) -> Value {
        if let cached = value(for: key) { return cached }
        let value = make()
        insert(value, for: key)
        return value
    }

    func removeAll() { values = [:]; order = [] }
}

/// Text maps of the pages read most recently, across books (keyed by book and page).
@MainActor
enum PageTextMaps {
    static let shared = RecentCache<String, PageTextMap>(capacity: 48)
}

extension Array {
    /// Whether two arrays share one buffer, so are equal without comparing their elements: the reader is handed the
    /// workspace's arrays on every SwiftUI update, and they are the very same arrays unless the workspace changed them.
    func sharesStorage(with other: [Element]) -> Bool {
        count == other.count && withUnsafeBufferPointer { mine in other.withUnsafeBufferPointer { theirs in mine.baseAddress == theirs.baseAddress } }
    }
}
