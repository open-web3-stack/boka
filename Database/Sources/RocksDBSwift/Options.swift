import Foundation
import rocksdb
import Utils

struct Options: ~Copyable, Sendable {
    let ptr: SafePointer

    var value: OpaquePointer { ptr.value }

    init() {
        ptr = .init(ptr: rocksdb_options_create(), free: rocksdb_options_destroy)
    }

    func increaseParallelism(cpus: Int) {
        rocksdb_options_increase_parallelism(ptr.value, Int32(cpus))
    }

    func optimizeLevelStyleCompaction(memtableMemoryBudget: UInt64) {
        rocksdb_options_optimize_level_style_compaction(ptr.value, memtableMemoryBudget)
    }

    func setCreateIfMissing(_ createIfMissing: Bool) {
        rocksdb_options_set_create_if_missing(ptr.value, createIfMissing ? 1 : 0)
    }

    func setLevelCompactionDynamicLevelBytes(_ levelCompactionDynamicLevelBytes: Bool) {
        rocksdb_options_set_level_compaction_dynamic_level_bytes(ptr.value, levelCompactionDynamicLevelBytes ? 1 : 0)
    }

    func setCreateIfMissingColumnFamilies(_ createIfMissingColumnFamilies: Bool) {
        rocksdb_options_set_create_missing_column_families(ptr.value, createIfMissingColumnFamilies ? 1 : 0)
    }
}

struct WriteOptions: ~Copyable, Sendable {
    let ptr: SafePointer

    var value: OpaquePointer { ptr.value }

    init() {
        ptr = .init(ptr: rocksdb_writeoptions_create(), free: rocksdb_writeoptions_destroy)
    }
}

public struct ReadOptions: ~Copyable, Sendable {
    let ptr: SafePointer

    var value: OpaquePointer { ptr.value }

    public init() {
        ptr = .init(ptr: rocksdb_readoptions_create(), free: rocksdb_readoptions_destroy)
    }

    public func setSnapshot(_ snapshot: borrowing Snapshot) {
        rocksdb_readoptions_set_snapshot(ptr.value, snapshot.value)
    }
}

public struct Snapshot: ~Copyable, Sendable {
    let ptr: SafePointer

    var value: OpaquePointer { ptr.value }

    init(_ db: SendableOpaquePointer) {
        ptr = .init(ptr: rocksdb_create_snapshot(db.value), free: { ptr in rocksdb_release_snapshot(db.value, ptr) })
    }
}

public struct Iterator: ~Copyable, Sendable {
    let ptr: SafePointer

    var value: OpaquePointer { ptr.value }

    init(_ db: OpaquePointer, readOptions: borrowing ReadOptions, columnFamily: OpaquePointer) {
        ptr = .init(
            ptr: rocksdb_create_iterator_cf(db, readOptions.value, columnFamily),
            free: rocksdb_iter_destroy
        )
    }

    public func seek(to key: Data) {
        key.withUnsafeBytes { rocksdb_iter_seek(ptr.value, $0.baseAddress, key.count) }
    }

    // read the key-value pair at the current position
    public func read() -> (key: Data, value: Data)? {
        read { pair -> (key: Data, value: Data)? in
            guard let pair else {
                return nil
            }
            // copy key and value

            let keyData = Data(buffer: pair.key)
            let valueData = Data(buffer: pair.value)
            return (key: keyData, value: valueData)
        }
    }

    /// read the key-value pair at the current position
    /// the passed key and values are only valid during the execution of the passed closure
    public func read<R>(fn: ((key: UnsafeBufferPointer<CChar>, value: UnsafeBufferPointer<CChar>)?) throws -> R) rethrows -> R {
        guard rocksdb_iter_valid(ptr.value) != 0 else {
            return try fn(nil)
        }

        var keyLength = 0
        var valueLength = 0
        let key = rocksdb_iter_key(ptr.value, &keyLength)
        let value = rocksdb_iter_value(ptr.value, &valueLength)

        guard let key, let value else {
            return try fn(nil)
        }

        let keyPtr = UnsafeBufferPointer(start: key, count: keyLength)
        let valuePtr = UnsafeBufferPointer(start: value, count: valueLength)

        return try fn((key: keyPtr, value: valuePtr))
    }

    public func next() {
        rocksdb_iter_next(ptr.value)
    }

    public func prev() {
        rocksdb_iter_prev(ptr.value)
    }
}
