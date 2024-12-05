import rocksdb
import Utils

public struct Options: ~Copyable, Sendable {
    let ptr: SafePointer

    var value: OpaquePointer { ptr.value }

    public init() {
        ptr = .init(ptr: rocksdb_options_create(), free: rocksdb_options_destroy)
    }

    public func increaseParallelism(cpus: Int) {
        rocksdb_options_increase_parallelism(ptr.value, Int32(cpus))
    }

    public func optimizeLevelStyleCompaction(memtableMemoryBudget: UInt64) {
        rocksdb_options_optimize_level_style_compaction(ptr.value, memtableMemoryBudget)
    }

    public func setCreateIfMissing(_ createIfMissing: Bool) {
        rocksdb_options_set_create_if_missing(ptr.value, createIfMissing ? 1 : 0)
    }

    public func setLevelCompactionDynamicLevelBytes(_ levelCompactionDynamicLevelBytes: Bool) {
        rocksdb_options_set_level_compaction_dynamic_level_bytes(ptr.value, levelCompactionDynamicLevelBytes ? 1 : 0)
    }

    public func setCreateIfMissingColumnFamilies(_ createIfMissingColumnFamilies: Bool) {
        rocksdb_options_set_create_missing_column_families(ptr.value, createIfMissingColumnFamilies ? 1 : 0)
    }
}

public struct WriteOptions: ~Copyable, Sendable {
    let ptr: SafePointer

    var value: OpaquePointer { ptr.value }

    public init() {
        ptr = .init(ptr: rocksdb_writeoptions_create(), free: rocksdb_writeoptions_destroy)
    }
}

public struct ReadOptions: ~Copyable, Sendable {
    let ptr: SafePointer

    var value: OpaquePointer { ptr.value }

    public init() {
        ptr = .init(ptr: rocksdb_readoptions_create(), free: rocksdb_readoptions_destroy)
    }
}
