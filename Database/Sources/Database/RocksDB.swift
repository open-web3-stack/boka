import Foundation
import rocksdb

public final class RocksDB {
    public enum BatchOperation {
        case delete(key: Data)
        case put(key: Data, value: Data)
    }

    public enum Error: Swift.Error {
        case openFailed(message: String)
        case putFailed(message: String)
        case getFailed(message: String)
        case deleteFailed(message: String)
        case batchFailed(message: String)
        case noData
    }

    private let dbOptions: OpaquePointer
    private let writeOptions: OpaquePointer
    private let readOptions: OpaquePointer
    private let db: OpaquePointer

    public init(path: URL) throws(Error) {
        let dbOptions = rocksdb_options_create()
        self.dbOptions = dbOptions!
        let cpus = sysconf(Int32(_SC_NPROCESSORS_ONLN))

        // Optimize rocksdb
        rocksdb_options_increase_parallelism(dbOptions, Int32(cpus))
        rocksdb_options_optimize_level_style_compaction(dbOptions, 0) // TODO: check this

        // create the DB if it's not already present
        rocksdb_options_set_create_if_missing(dbOptions, 1)

        // create writeoptions
        writeOptions = rocksdb_writeoptions_create()
        // create readoptions
        readOptions = rocksdb_readoptions_create()

        // open DB
        db = try Self.call { err, _ in
            rocksdb_open(dbOptions, path.path, &err)
        } onErr: { message throws(Error) in
            throw Error.openFailed(message: message)
        }
    }

    deinit {
        rocksdb_writeoptions_destroy(writeOptions)
        rocksdb_readoptions_destroy(readOptions)
        rocksdb_options_destroy(dbOptions)
        rocksdb_close(db)
    }
}

// MARK: - private helpers

extension RocksDB {
    private static func call<R>(
        _ data: [Data],
        fn: (inout UnsafeMutablePointer<Int8>?, [(ptr: UnsafeRawPointer, count: Int)]) -> R,
        // need new swiftlint version https://github.com/realm/SwiftLint/issues/5631
        // swiftlint:disable:next identifier_name
        onErr: (String) throws(Error) -> Void
    ) throws(Error) -> R {
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
            return first.withUnsafeBytes {
                (bufferPtr: UnsafeRawBufferPointer) -> Result<R, Error> in
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
        onErr: (String) throws(Error) -> Void
    ) throws(Error) -> R {
        try call(data, fn: fn, onErr: onErr)
    }

    private static func call<R>(
        _ data: Data...,
        fn: ([(ptr: UnsafeRawPointer, count: Int)]) -> R
    ) throws(Error) -> R {
        try call(data) { _, ptrs in
            fn(ptrs)
        } onErr: { _ throws(Error) in
            // do nothing as it should never be called
        }
    }
}

// MARK: - public methods

extension RocksDB {
    public func put(key: Data, value: Data) throws(Error) {
        try Self.call(key, value) { err, ptrs in
            let key = ptrs[0]
            let value = ptrs[1]
            rocksdb_put(db, writeOptions, key.ptr, key.count, value.ptr, value.count, &err)
        } onErr: { message throws(Error) in
            throw Error.putFailed(message: message)
        }
    }

    public func get(key: Data) throws -> Data? {
        var len = 0

        let ret = try Self.call(key) { err, ptrs in
            let key = ptrs[0]
            return rocksdb_get(db, readOptions, key.ptr, key.count, &len, &err)
        } onErr: { message throws(Error) in
            throw Error.getFailed(message: message)
        }

        defer {
            free(ret)
        }

        return ret.map { Data(bytes: $0, count: len) }
    }

    public func delete(key: Data) throws {
        try Self.call(key) { err, ptrs in
            let key = ptrs[0]
            rocksdb_delete(db, writeOptions, key.ptr, key.count, &err)
        } onErr: { message throws(Error) in
            throw Error.deleteFailed(message: message)
        }
    }

    public func batch(operations: [BatchOperation]) throws {
        let writeBatch = rocksdb_writebatch_create()
        defer { rocksdb_writebatch_destroy(writeBatch) }

        for operation in operations {
            switch operation {
            case let .delete(key):
                try Self.call(key) { ptrs in
                    let key = ptrs[0]
                    rocksdb_writebatch_delete(writeBatch, key.ptr, key.count)
                }

            case let .put(key, value):
                try Self.call(key, value) { ptrs in
                    let key = ptrs[0]
                    let value = ptrs[1]

                    rocksdb_writebatch_put(writeBatch, key.ptr, key.count, value.ptr, value.count)
                }
            }
        }

        try Self.call { err, _ in
            rocksdb_write(db, writeOptions, writeBatch, &err)
        } onErr: { message throws(Error) in
            throw Error.batchFailed(message: message)
        }
    }
}
