import Foundation
import rocksdb
import Utils

public protocol ColumnFamilyKey: Sendable, CaseIterable, Hashable, RawRepresentable<UInt8> {}

public final class RocksDB<CFKey: ColumnFamilyKey>: Sendable {
    public enum BatchOperation {
        case delete(column: CFKey, key: Data)
        case put(column: CFKey, key: Data, value: Data)
    }

    public enum Error: Swift.Error {
        case openFailed(message: String)
        case putFailed(message: String)
        case getFailed(message: String)
        case deleteFailed(message: String)
        case batchFailed(message: String)
        case noData
    }

    private let writeOptions: WriteOptions
    private let readOptions: ReadOptions
    private let db: SafePointer
    private let cfHandles: [SendableOpaquePointer]

    public init(path: URL) throws {
        let dbOptions = Options()

        // TODO: starting from options here
        // https://github.com/paritytech/parity-common/blob/e3787dc768b08e10809834c65419ad3c255b5cac/kvdb-rocksdb/src/lib.rs#L339

        let cpus = sysconf(Int32(_SC_NPROCESSORS_ONLN))
        dbOptions.increaseParallelism(cpus: cpus)
        dbOptions.optimizeLevelStyleCompaction(memtableMemoryBudget: 512 * 1024 * 1024) // 512 MB
        dbOptions.setCreateIfMissing(true)
        dbOptions.setCreateIfMissingColumnFamilies(true)

        let cfOptions = Options()
        cfOptions.setLevelCompactionDynamicLevelBytes(true)

        var names = CFKey.allCases.map { "\($0)" }
        // ensure always have a default column family
        if !names.contains("default") {
            names.insert("default", at: 0)
        }
        var cfOptionsList = names.map { _ in cfOptions.value as OpaquePointer? }

        var outHandles = [OpaquePointer?](repeating: nil, count: names.count)

        // open DB
        let dbPtr = try FFIUtils.withCString(names) { cnames in
            var cnames = cnames
            return try Self.call { err, _ in
                rocksdb_open_column_families(
                    dbOptions.value,
                    path.path,
                    Int32(names.count),
                    &cnames,
                    &cfOptionsList,
                    &outHandles,
                    &err
                )
            } onErr: { message throws in
                throw Error.openFailed(message: message)
            }
        }

        db = SafePointer(ptr: dbPtr!, free: rocksdb_close)

        cfHandles = outHandles.map { $0!.asSendable }

        writeOptions = WriteOptions()
        readOptions = ReadOptions()
    }

    deinit {
        for handle in cfHandles {
            rocksdb_column_family_handle_destroy(handle.value)
        }
    }
}

// MARK: - private helpers

extension RocksDB {
    private static func call<R>(
        _ data: [Data],
        fn: (inout UnsafeMutablePointer<Int8>?, [(ptr: UnsafeRawPointer, count: Int)]) -> R,
        onErr: (String) throws -> Void
    ) throws -> R {
        var err: UnsafeMutablePointer<Int8>?
        defer {
            free(err)
        }

        func helper(data: ArraySlice<Data>, ptr: [(ptr: UnsafeRawPointer, count: Int)]) -> Result<
            R, Error
        > {
            if data.isEmpty {
                return .success(fn(&err, ptr))
            }
            let rest = data.dropFirst()
            let first = data.first!
            return first.withUnsafeBytes { (bufferPtr: UnsafeRawBufferPointer) -> Result<R, Error> in
                guard let bufferAddress = bufferPtr.baseAddress else {
                    return .failure(.noData)
                }
                return helper(data: rest, ptr: ptr + [(bufferAddress, bufferPtr.count)])
            }
        }

        let ret = helper(data: data[...], ptr: [])

        switch ret {
        case let .success(value):
            if let pointee = err {
                let message = String(cString: pointee)
                try onErr(message)
            }
            return value
        case let .failure(error):
            throw error
        }
    }

    private static func call<R>(
        _ data: Data...,
        fn: (inout UnsafeMutablePointer<Int8>?, [(ptr: UnsafeRawPointer, count: Int)]) -> R,
        onErr: (String) throws -> Void
    ) throws -> R {
        try call(data, fn: fn, onErr: onErr)
    }

    private static func call<R>(
        _ data: Data...,
        fn: ([(ptr: UnsafeRawPointer, count: Int)]) -> R
    ) throws -> R {
        try call(data) { _, ptrs in
            fn(ptrs)
        } onErr: { _ throws in
            // do nothing as it should never be called
        }
    }

    private func getHandle(column: CFKey) -> OpaquePointer {
        cfHandles[Int(column.rawValue)].value
    }
}

// MARK: - public methods

extension RocksDB {
    public func put(column: CFKey, key: Data, value: Data) throws {
        let handle = getHandle(column: column)
        try Self.call(key, value) { err, ptrs in
            let key = ptrs[0]
            let value = ptrs[1]
            rocksdb_put_cf(
                db.value,
                writeOptions.value,
                handle,
                key.ptr,
                key.count,
                value.ptr,
                value.count,
                &err
            )
        } onErr: { message throws in
            throw Error.putFailed(message: message)
        }
    }

    public func get(column: CFKey, key: Data) throws -> Data? {
        var len = 0
        let handle = getHandle(column: column)

        let ret = try Self.call(key) { err, ptrs in
            let key = ptrs[0]
            return rocksdb_get_cf(db.value, readOptions.value, handle, key.ptr, key.count, &len, &err)
        } onErr: { message throws in
            throw Error.getFailed(message: message)
        }

        return ret.map { Data(bytesNoCopy: $0, count: len, deallocator: .free) }
    }

    public func delete(column: CFKey, key: Data) throws {
        let handle = getHandle(column: column)

        try Self.call(key) { err, ptrs in
            let key = ptrs[0]
            rocksdb_delete_cf(db.value, writeOptions.value, handle, key.ptr, key.count, &err)
        } onErr: { message throws in
            throw Error.deleteFailed(message: message)
        }
    }

    public func batch(operations: [BatchOperation]) throws {
        let writeBatch = rocksdb_writebatch_create()
        defer { rocksdb_writebatch_destroy(writeBatch) }

        for operation in operations {
            switch operation {
            case let .delete(column, key):
                let handle = getHandle(column: column)
                try Self.call(key) { ptrs in
                    let key = ptrs[0]
                    rocksdb_writebatch_delete_cf(writeBatch, handle, key.ptr, key.count)
                }

            case let .put(column, key, value):
                let handle = getHandle(column: column)
                try Self.call(key, value) { ptrs in
                    let key = ptrs[0]
                    let value = ptrs[1]

                    rocksdb_writebatch_put_cf(writeBatch, handle, key.ptr, key.count, value.ptr, value.count)
                }
            }
        }

        try Self.call { err, _ in
            rocksdb_write(db.value, writeOptions.value, writeBatch, &err)
        } onErr: { message throws in
            throw Error.batchFailed(message: message)
        }
    }
}
