import erasure_coding
import Foundation

public enum ErasureCoding {
    public enum Error: Swift.Error, Equatable {
        case newShardFailed(Int)
        case encodeFailed(Int)
        case recoveryFailed(Int)
        case getDataFailed(Int)
        case getIndexFailed(Int)
        case reconstructFailed
        case shardSizeTooSmall
    }

    public enum Constants {
        // 2 in GP, but the reed_solomon_simd library fails to recover shard size < 16
        public static let INNER_SHARD_SIZE: Int = 16
    }

    // Note that `Shard` and `InnerShard` have the same data structure, but `Shard`s are larger data and for external usage,
    // and `InnerShard`s are smaller data that are used in ffi to do the actual erasure coding
    public struct Shard {
        public let data: Data
        public let index: UInt32
    }

    public final class InnerShard {
        fileprivate let ptr: SafePointer
        let size: Int

        var data: Data? {
            var dataPtr: UnsafePointer<UInt8>?
            try? FFIUtils.call { _ in
                shard_get_data(ptr.ptr.value, &dataPtr)
            } onErr: { err throws(Error) in
                throw .getDataFailed(err)
            }
            guard let dataPtr else { return nil }
            return Data(bytes: dataPtr, count: size)
        }

        var index: UInt32? {
            var result: UInt32 = 0
            try? FFIUtils.call { _ in
                shard_get_index(ptr.ptr.value, &result)
            } onErr: { err throws(Error) in
                throw .getIndexFailed(err)
            }
            return result
        }

        public init(data: Data, index: UInt32) throws(Error) {
            var ptr: OpaquePointer!

            try FFIUtils.call(data) { ptrs in
                shard_new(ptrs[0].ptr, ptrs[0].count, index, &ptr)
            } onErr: { err throws(Error) in
                throw .newShardFailed(err)
            }

            self.ptr = SafePointer(ptr: ptr, free: shard_free)
            size = data.count
        }
    }

    /// split data of length k * n into k data of length n (with padding if no enough)
    static func split(data: Data, n: Int) -> [Data] {
        guard n > 0 else { return [] }

        var padded = data
        let remainder = padded.count % n
        if remainder != 0 {
            padded.append(Data(repeating: 0, count: n - remainder))
        }

        let k = padded.count / n
        var result: [Data] = []

        for i in 0 ..< k {
            let start = i * n
            let chunk = padded[relative: start ..< start + n]
            result.append(chunk)
        }

        return result
    }

    /// join k data of length n into one data of length k * n
    static func join(arr: [Data], n: Int) -> Data {
        var result = Data(capacity: arr.count * n)

        for var d in arr {
            if d.count < n {
                d.append(Data(repeating: 0, count: n - d.count))
            } else if d.count > n {
                d = d.prefix(n)
            }
            result.append(d)
        }

        return result
    }

    /// unzip data of length k * n into k data of length n
    static func unzip(data: Data, n: Int) -> [Data] {
        guard n > 0 else { return [] }

        var padded = data
        let total = padded.count
        let remainder = total % n
        if remainder != 0 {
            padded.append(Data(repeating: 0, count: n - remainder))
        }

        let k = padded.count / n
        var result = Array(repeating: Data(), count: k)

        for i in 0 ..< k {
            for j in 0 ..< n {
                result[i].append(padded[i + j * k])
            }
        }

        return result
    }

    /// lace k data of length n into one data of length k * n
    static func lace(arr: [Data], n: Int) -> Data {
        let k = arr.count
        var result = Data(capacity: k * n)

        for j in 0 ..< n {
            for i in 0 ..< k {
                if j < arr[i].count {
                    result.append(arr[i][j])
                } else {
                    result.append(0)
                }
            }
        }
        return result
    }

    static func transpose<T>(_ matrix: [[T]]) -> [[T]] {
        guard let firstRow = matrix.first else { return [] }

        let rowCount = matrix.count
        let colCount = firstRow.count

        return (0 ..< colCount).map { colIndex in
            (0 ..< rowCount).map { rowIndex in
                matrix[rowIndex][colIndex]
            }
        }
    }

    /// C: encode original shards into recovery shards
    public static func encode(original: [Data], recoveryCount: Int) throws -> [Data] {
        let originalCount = original.count
        let shardSize = original[0].count

        guard shardSize >= Constants.INNER_SHARD_SIZE else { throw Error.shardSizeTooSmall }

        // output recovery shards
        var recoveryPtrs = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: recoveryCount)
        defer {
            for ptr in recoveryPtrs {
                ptr?.deallocate()
            }
        }
        for i in 0 ..< recoveryCount {
            recoveryPtrs[i] = UnsafeMutablePointer<UInt8>.allocate(capacity: shardSize)
            recoveryPtrs[i]?.initialize(repeating: 0, count: shardSize)
        }

        // original shards pointers
        var originalPtrs = [UnsafePointer<UInt8>?](repeating: nil, count: originalCount)
        for i in 0 ..< originalCount {
            original[i].withUnsafeBytes { bytes in
                originalPtrs[i] = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
            }
        }

        let result = reed_solomon_encode(
            originalPtrs,
            UInt(originalCount),
            UInt(recoveryCount),
            UInt(shardSize),
            &recoveryPtrs
        )

        if result != 0 {
            throw Error.encodeFailed(result)
        }

        var recoveryShards = [Data](repeating: Data(repeating: 0, count: shardSize), count: recoveryCount)
        for i in 0 ..< recoveryCount {
            if let ptr = recoveryPtrs[i] {
                recoveryShards[i] = Data(bytes: ptr, count: shardSize)
            }
        }

        return recoveryShards
    }

    /// R: recover original shards from recovery and/or original shards
    /// - Parameters:
    ///   - originalCount: total number of original shards
    ///   - recoveryCount: total number of recovery shards
    ///   - recovery: provide any recovery shards
    ///   - shardSize: size of each shard
    public static func recover(
        originalCount: Int,
        recoveryCount: Int,
        recovery: [InnerShard],
        shardSize: Int
    ) throws -> [Data] {
        guard shardSize >= Constants.INNER_SHARD_SIZE else { throw Error.shardSizeTooSmall }

        // output original shards
        var originalPtrs = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: originalCount)
        for i in 0 ..< originalCount {
            originalPtrs[i] = UnsafeMutablePointer<UInt8>.allocate(capacity: shardSize)
            originalPtrs[i]?.initialize(repeating: 0, count: shardSize)
        }

        defer {
            for ptr in originalPtrs {
                ptr?.deallocate()
            }
        }

        try FFIUtils.call { _ in
            // use arrays of OpaquePointer directly without copying SafePointer
            var recoveryOpaquePtrs = [OpaquePointer?](repeating: nil, count: recovery.count)

            for (i, shard) in recovery.enumerated() {
                recoveryOpaquePtrs[i] = shard.ptr.value
            }

            return recoveryOpaquePtrs.withUnsafeBufferPointer { recoveryBuffer in
                reed_solomon_recovery(
                    UInt(originalCount),
                    UInt(recoveryCount),
                    recoveryBuffer.baseAddress,
                    UInt(recovery.count),
                    UInt(shardSize),
                    &originalPtrs
                )
            }
        } onErr: { err throws(Error) in
            throw .recoveryFailed(err)
        }

        var recoveredShards = [Data](repeating: Data(), count: originalCount)
        for i in 0 ..< originalCount {
            if let ptr = originalPtrs[i] {
                recoveredShards[i] = Data(bytes: ptr, count: shardSize)
            }
        }

        return recoveredShards
    }

    /// C_k: erasure-code chunking function (eq H.6)
    /// - Parameters:
    ///   - data: the original data
    ///   - originalCount: ≈ 2 * number of cores; 684 for full config, aka `W_E`. Note that `k` will be `|data| / originalCount`
    ///   - recoveryCount: ≈ number of validators; 1023 for full config
    /// - Returns: the list of smaller data chunks
    public static func chunk(data: Data, originalCount: Int, recoveryCount: Int) throws -> [Data] {
        var result: [Data] = []

        let unzipped = unzip(data: data, n: originalCount)

        var matrix: [[Data]] = []

        for original in unzipped {
            let originalShards = split(data: original, n: Constants.INNER_SHARD_SIZE)
            let recoveryShards = try encode(original: originalShards, recoveryCount: recoveryCount)
            matrix.append(recoveryShards)
        }

        let transposed = transpose(matrix)

        for row in transposed {
            let joined = join(arr: row, n: Constants.INNER_SHARD_SIZE)
            result.append(joined)
        }

        return result
    }

    /// R_k: erasure-code reconstruction function (eq H.7)
    /// - Parameters:
    ///   - shards: the shards to reconstruct the original data, should be ordered
    ///   - originalCount: the total number of original items
    ///   - recoveryCount: the total number of recovery items
    /// - Returns: the reconstructed original data
    public static func reconstruct(shards: [Shard], originalCount: Int, recoveryCount: Int) throws -> Data {
        if shards.isEmpty { return Data() }

        let shardSize = shards[0].data.count
        let k = (shardSize + Constants.INNER_SHARD_SIZE - 1) / Constants.INNER_SHARD_SIZE

        let splitted = shards.map { split(data: $0.data, n: Constants.INNER_SHARD_SIZE) }

        var result = [Data](repeating: Data(), count: k)

        for p in 0 ..< k {
            var recoveryShards: [InnerShard] = []

            for i in shards.indices {
                try recoveryShards.append(.init(data: splitted[i][p], index: UInt32(i)))
            }

            let originalShards = try recover(
                originalCount: originalCount,
                recoveryCount: recoveryCount,
                recovery: recoveryShards,
                shardSize: Constants.INNER_SHARD_SIZE
            )

            let originalData = join(arr: originalShards, n: Constants.INNER_SHARD_SIZE)

            result[p] = originalData
        }

        return lace(arr: result, n: originalCount)
    }
}
