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
        case invalidBasicSize(Int)
        case invalidShardsCount
    }

    public enum Constants {
        public static let INNER_SHARD_SIZE: Int = 2
    }

    // Note that `Shard` and `InnerShard` have the same data structure, but `Shard`s are larger data and for external usage,
    // and `InnerShard`s are smaller data that are used in ffi to do the actual erasure coding
    public struct Shard {
        public let data: Data
        public let index: UInt32

        public init(data: Data, index: UInt32) {
            self.data = data
            self.index = index
        }
    }

    final class InnerShard {
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
    static func encode(original: [Data], recoveryCount: Int) throws -> [Data] {
        guard !original.isEmpty else { return [] }

        let originalCount = original.count
        let shardSize = original[0].count

        var originalBuffers: [UnsafeMutableBufferPointer<UInt8>] = []
        for shard in original {
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: shardSize)
            _ = buffer.initialize(from: shard)
            originalBuffers.append(buffer)
        }

        var recoveryBuffers: [UnsafeMutableBufferPointer<UInt8>] = []
        for _ in 0 ..< recoveryCount {
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: shardSize)
            buffer.initialize(repeating: 0)
            recoveryBuffers.append(buffer)
        }

        defer {
            for buffer in originalBuffers {
                buffer.deallocate()
            }
            for buffer in recoveryBuffers {
                buffer.deallocate()
            }
        }

        var originalPtrs = originalBuffers.map { UnsafePointer<UInt8>($0.baseAddress) }
        var recoveryPtrs = recoveryBuffers.map(\.baseAddress)

        try FFIUtils.call { _ in
            reed_solomon_encode(
                &originalPtrs,
                UInt(originalCount),
                UInt(recoveryCount),
                UInt(shardSize),
                &recoveryPtrs
            )
        } onErr: { err throws(Error) in
            throw .encodeFailed(err)
        }

        var recovery = [Data]()
        for i in 0 ..< recoveryCount {
            let data = Data(bytes: recoveryBuffers[i].baseAddress!, count: shardSize)
            recovery.append(data)
        }

        return recovery
    }

    /// R: recover original shards from recovery and/or original shards
    /// - Parameters:
    ///   - originalCount: total number of original shards
    ///   - recoveryCount: total number of recovery shards
    ///   - recovery: provide any recovery shards, at least originalCount of items
    ///   - shardSize: size of each shard
    static func recover(
        originalCount: Int,
        recoveryCount: Int,
        recovery: [InnerShard],
        shardSize: Int
    ) throws -> [Data] {
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

        // use arrays of OpaquePointer directly without copying SafePointer
        var recoveryOpaquePtrs = [OpaquePointer?](repeating: nil, count: recovery.count)

        for (i, shard) in recovery.enumerated() {
            recoveryOpaquePtrs[i] = shard.ptr.value
        }

        try FFIUtils.call { _ in
            recoveryOpaquePtrs.withUnsafeBufferPointer { recoveryBuffer in
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
    ///   - basicSize: ≈ 2 * number of cores; 684 for full config. Note that `k` will be `|data| / basicSize`
    ///   - recoveryCount: ≈ number of validators; 1023 for full config
    /// - Returns: the list of smaller data chunks
    public static func chunk(data: Data, basicSize: Int, recoveryCount: Int) throws -> [Data] {
        var result: [Data] = []

        guard basicSize % 2 == 0 else { throw Error.invalidBasicSize(basicSize) }

        let unzipped = unzip(data: data, n: basicSize)

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
    ///   - basicSize: ≈ 2 * number of cores; 684 for full config. Note that `k` will be `|data| / basicSize`
    ///   - originalCount: the total number of original items
    ///   - recoveryCount: the total number of recovery items
    /// - Returns: the reconstructed original data
    public static func reconstruct(shards: [Shard], basicSize: Int, originalCount: Int, recoveryCount: Int) throws -> Data {
        if shards.isEmpty { return Data() }

        guard basicSize % 2 == 0 else { throw Error.invalidBasicSize(basicSize) }
        guard shards.count >= originalCount else {
            throw Error.invalidShardsCount
        }

        let shardSize = shards[0].data.count
        let k = (shardSize + Constants.INNER_SHARD_SIZE - 1) / Constants.INNER_SHARD_SIZE

        let splitted = shards.map { split(data: $0.data, n: Constants.INNER_SHARD_SIZE) }

        var result = [Data](repeating: Data(), count: k)

        for p in 0 ..< k {
            var recoveryShards: [InnerShard] = []

            for i in shards.indices {
                try recoveryShards.append(.init(data: splitted[i][p], index: UInt32(shards[i].index)))
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

        return lace(arr: result, n: basicSize)
    }
}
