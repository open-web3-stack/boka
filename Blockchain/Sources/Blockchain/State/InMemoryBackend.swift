import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "InMemoryBackend")

public actor InMemoryBackend: StateBackendProtocol {
    // Use Dictionary for O(1) lookups
    private var store: [Data: Data] = [:]
    private var rawValues: [Data32: Data] = [:]
    public private(set) var refCounts: [Data: Int] = [:]
    private var rawValueRefCounts: [Data32: Int] = [:]

    public init() {}

    public func read(key: Data) async throws -> Data? {
        store[key]
    }

    public func readAll(prefix: Data, startKey: Data?, limit: UInt32?) async throws -> [(key: Data, value: Data)] {
        var resp = [(key: Data, value: Data)]()

        if let limit {
            resp.reserveCapacity(Int(limit))
        }

        let startKey = startKey ?? prefix

        // Filter and sort entries
        let filtered = store
            .filter { $0.key.starts(with: prefix) && !$0.key.lexicographicallyPrecedes(startKey) }
            .sorted { $0.key.lexicographicallyPrecedes($1.key) }

        // Apply limit if specified
        if let limit {
            return Array(filtered.prefix(Int(limit)))
        }

        return filtered
    }

    public func batchUpdate(_ updates: [StateBackendOperation]) async throws {
        logger.info("batchUpdate: Processing \(updates.count) operations")
        for update in updates {
            switch update {
            case let .write(key, value):
                store[key] = value
            case let .writeRawValue(key, value):
                rawValues[key] = value
                rawValueRefCounts[key, default: 0] += 1
            case let .refUpdate(key, delta):
                let oldCount = refCounts[key, default: 0]
                refCounts[key, default: 0] += Int(delta)
                let newCount = refCounts[key]!
                if delta != 0 {
                    logger.info("refUpdate: key=\(key.toHexString()), delta=\(delta), oldCount=\(oldCount), newCount=\(newCount)")
                }
            }
        }
    }

    public func readValue(hash: Data32) async throws -> Data? {
        rawValues[hash]
    }

    public func batchRead(keys: [Data]) async throws -> [Data: Data] {
        var result: [Data: Data] = [:]
        // In-memory implementation: direct dictionary lookup
        for key in keys {
            if let value = store[key] {
                result[key] = value
            }
        }
        return result
    }

    public func gc(callback: @Sendable (Data) -> Data32?) async throws {
        // check ref counts and remove keys with 0 ref count
        var keysToRemove: [Data] = []
        logger.info("GC: Starting garbage collection, total keys in refCounts: \(refCounts.count), store: \(store.count)")

        for (key, count) in refCounts where count == 0 {
            if let value = store[key] {
                logger.info("GC: Removing zero-ref key: \(key.toHexString())")
                store.removeValue(forKey: key)
                keysToRemove.append(key)
                if let rawValueKey = callback(value) {
                    rawValueRefCounts[rawValueKey, default: 0] -= 1
                    if rawValueRefCounts[rawValueKey] == 0 {
                        logger.info("GC: Removing zero-ref raw value: \(rawValueKey.toHexString())")
                        rawValues.removeValue(forKey: rawValueKey)
                        rawValueRefCounts.removeValue(forKey: rawValueKey)
                    }
                }
            } else {
                logger.warning("GC: Key in refCounts but not in store: \(key.toHexString())")
            }
        }

        // Remove keys from refCounts to prevent unbounded growth
        for key in keysToRemove {
            refCounts.removeValue(forKey: key)
        }

        logger.info("GC: Removed \(keysToRemove.count) keys, remaining: \(store.count) in store, \(refCounts.count) in refCounts")

        // Log remaining non-zero ref counts for debugging
        let nonZeroRefs = refCounts.filter { $0.value > 0 }
        if !nonZeroRefs.isEmpty {
            logger.info("GC: Remaining non-zero ref counts: \(nonZeroRefs.count) keys")
            // Log a few sample keys
            for (key, count) in nonZeroRefs.prefix(5) {
                logger.info("  key: \(key.toHexString()), ref count: \(count)")
            }
        }
    }

    public func debugPrint() {
        for (key, value) in store {
            let refCount = refCounts[key, default: 0]
            logger.info("key: \(key.toHexString())")
            logger.info("value: \(value.toHexString())")
            logger.info("ref count: \(refCount)")
        }
    }

    /// Get reference count for a key (for testing purposes)
    public func getRefCount(key: Data) async -> Int {
        refCounts[key] ?? 0
    }

    public func createIterator(prefix: Data, startKey: Data?) async throws -> StateBackendIterator {
        // Create sorted array of matching items
        let searchKey = startKey ?? prefix
        let matchingItems = store
            .filter { $0.key.starts(with: prefix) && !$0.key.lexicographicallyPrecedes(searchKey) }
            .sorted { $0.key.lexicographicallyPrecedes($1.key) }

        return InMemoryStateIterator(items: matchingItems)
    }
}

/// Iterator over in-memory state backend entries
///
/// Thread-safety: @unchecked Sendable is safe here because:
/// - Iterator is created from a snapshot (immutable array copy)
/// - Each iterator instance is owned by a single caller
/// - Not shared across concurrent operations
public final class InMemoryStateIterator: StateBackendIterator, @unchecked Sendable {
    private var iterator: Array<(key: Data, value: Data)>.Iterator

    init(items: [(key: Data, value: Data)]) {
        iterator = items.makeIterator()
    }

    public func next() async throws -> (key: Data, value: Data)? {
        iterator.next()
    }
}
