import Codec
import Foundation
import Utils

private struct KVPair: Comparable, Sendable {
    var key: Data
    var value: Data

    public static func < (lhs: KVPair, rhs: KVPair) -> Bool {
        lhs.key.lexicographicallyPrecedes(rhs.key)
    }
}

public actor InMemoryBackend: StateBackendProtocol {
    private var store: SortedArray<KVPair>
    private var refCounts: [Data: Int]

    public init(store: [Data32: Data] = [:]) {
        self.store = .init(store.map { KVPair(key: $0.key.data, value: $0.value) })
        refCounts = [:]

        for key in store.keys {
            refCounts[key.data] = 1
        }
    }

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

    public func batchRead(keys: [Data]) async throws -> [(key: Data, value: Data?)] {
        var resp = [(key: Data, value: Data?)]()
        for key in keys {
            let value = try await read(key: key)
            resp.append((key, value))
        }
        return resp
    }

    public func batchUpdate(_: [StateBackendOperation]) async throws {}

    public func gc() async throws {
        // check ref counts and remove keys with 0 ref count
        for (key, count) in refCounts where count == 0 {
            let idx = store.insertIndex(KVPair(key: key, value: Data()))
            if store.array[safe: idx]?.key == key {
                store.remove(at: idx)
            }
        }
    }
}
