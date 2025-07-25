import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "InMemoryBackend")

public actor InMemoryBackend: StateBackendProtocol {
    public struct KVPair: Comparable, Sendable {
        var key: Data
        var value: Data

        public static func < (lhs: KVPair, rhs: KVPair) -> Bool {
            lhs.key.lexicographicallyPrecedes(rhs.key)
        }
    }

    // we really should be using Heap or some other Tree based structure here
    // but let's keep it simple for now
    public private(set) var store: SortedArray<KVPair> = .init([])
    private var rawValues: [Data32: Data] = [:]
    public private(set) var refCounts: [Data: Int] = [:]
    private var rawValueRefCounts: [Data32: Int] = [:]

    public init() {}

    public func read(key: Data) async throws -> Data? {
        let idx = store.insertIndex(KVPair(key: key, value: Data()))
        let item = store.array[safe: idx]
        if item?.key == key {
            return item?.value
        }
        return nil
    }

    public func readAll(prefix: Data, startKey: Data?, limit: UInt32?) async throws -> [(key: Data, value: Data)] {
        var resp = [(key: Data, value: Data)]()

        if let limit {
            resp.reserveCapacity(Int(limit))
        }

        let startKey = startKey ?? prefix
        let startIndex = store.insertIndex(KVPair(key: startKey, value: Data()))
        for i in startIndex ..< store.array.count {
            let item = store.array[i]
            if item.key.starts(with: prefix) {
                resp.append((item.key, item.value))
            } else {
                break
            }
            if let limit, resp.count == limit {
                break
            }
        }
        return resp
    }

    public func batchUpdate(_ updates: [StateBackendOperation]) async throws {
        for update in updates {
            switch update {
            case let .write(key, value):
                let idx = store.insertIndex(KVPair(key: key, value: value))
                let item = store.array[safe: idx]
                if let item, item.key == key { // found
                    // value is not used for ordering so this is safe
                    store.unsafeArrayAccess[idx].value = value
                } else { // not found
                    store.insert(KVPair(key: key, value: value))
                }
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
        for (key, count) in refCounts where count == 0 {
            let idx = store.insertIndex(KVPair(key: key, value: Data()))
            let item = store.array[safe: idx]
            if let item, item.key == key {
                store.remove(at: idx)
                if let rawValueKey = callback(item.value) {
                    rawValueRefCounts[rawValueKey, default: 0] -= 1
                    if rawValueRefCounts[rawValueKey] == 0 {
                        rawValues.removeValue(forKey: rawValueKey)
                        rawValueRefCounts.removeValue(forKey: rawValueKey)
                    }
                }
            }
        }
    }

    public func debugPrint() {
        for item in store.array {
            let refCount = refCounts[item.key, default: 0]
            logger.info("key: \(item.key.toHexString())")
            logger.info("value: \(item.value.toHexString())")
            logger.info("ref count: \(refCount)")
        }
    }

    public func createIterator(prefix: Data, startKey: Data?) async throws -> StateBackendIterator {
        InMemoryStateIterator(store: store, prefix: prefix, startKey: startKey)
    }
}

public final class InMemoryStateIterator: StateBackendIterator, @unchecked Sendable {
    private var iterator: Array<(key: Data, value: Data)>.Iterator

    init(store: SortedArray<InMemoryBackend.KVPair>, prefix: Data, startKey: Data?) {
        let searchKey = startKey ?? prefix
        let startIndex = store.insertIndex(InMemoryBackend.KVPair(key: searchKey, value: Data()))

        let matchingItems = Array(store.array[startIndex...].prefix { item in
            item.key.starts(with: prefix)
        }.map { (key: $0.key, value: $0.value) })

        iterator = matchingItems.makeIterator()
    }

    public func next() async throws -> (key: Data, value: Data)? {
        iterator.next()
    }
}
