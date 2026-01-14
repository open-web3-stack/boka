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
        for update in updates {
            switch update {
            case let .write(key, value):
                store[key] = value
            case let .writeRawValue(key, value):
                rawValues[key] = value
                rawValueRefCounts[key, default: 0] += 1
            case let .refIncrement(key):
                refCounts[key, default: 0] += 1
            case let .refDecrement(key):
                refCounts[key, default: 0] -= 1
            }
        }
    }

    public func readValue(hash: Data32) async throws -> Data? {
        rawValues[hash]
    }

    public func gc(callback: @Sendable (Data) -> Data32?) async throws {
        // check ref counts and remove keys with 0 ref count
        var keysToRemove: [Data] = []
        for (key, count) in refCounts where count == 0 {
            if let value = store[key] {
                store.removeValue(forKey: key)
                keysToRemove.append(key)
                if let rawValueKey = callback(value) {
                    rawValueRefCounts[rawValueKey, default: 0] -= 1
                    if rawValueRefCounts[rawValueKey] == 0 {
                        rawValues.removeValue(forKey: rawValueKey)
                        rawValueRefCounts.removeValue(forKey: rawValueKey)
                    }
                }
            }
        }
        // Remove keys from refCounts to prevent unbounded growth
        for key in keysToRemove {
            refCounts.removeValue(forKey: key)
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
