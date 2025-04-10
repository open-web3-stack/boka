import erasure_coding
import Foundation

public enum ErasureCoding {
    public enum Error: Swift.Error {
        case newShardFailed(Int)
        case encodeFailed(Int)
        case recoveryFailed(Int)
        case getDataFailed(Int)
        case getIndexFailed(Int)
        case reconstructFailed
    }

    // Note that `Shard` and `InnerShard` have the same data structure, but `Shard`s are larger data and for external usage,
    // and `InnerShard`s are smaller data that are used in ffi to do the actual erasure coding
    public struct Shard {
        public let data: Data
        public let index: UInt32
    }

    final class InnerShard {
        fileprivate let ptr: SafePointer
        let size: Int

        // var data: Data? {
        //     var dataPtr: UnsafePointer<UInt8>?
        //     try? FFIUtils.call { _ in
        //         shard_get_data(ptr.ptr.value, &dataPtr)
        //     } onErr: { err throws(Error) in
        //         throw .getDataFailed(err)
        //     }
        //     guard let dataPtr else { return nil }
        //     return Data(bytes: dataPtr, count: size)
        // }

        // var index: UInt32? {
        //     var result: UInt32 = 0
        //     try? FFIUtils.call { _ in
        //         shard_get_index(ptr.ptr.value, &result)
        //     } onErr: { err throws(Error) in
        //         throw .getIndexFailed(err)
        //     }
        //     return result
        // }

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

    /// lace unzipped k data of length n into one data of length k * n
    static func lace(arr: [Data], n: Int) -> Data {
        let k = arr.count
        var result = Data(capacity: k * n)

        for j in 0 ..< n {
            for i in 0 ..< k {
                result.append(arr[i][j])
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
        let originalCount = original.count
        let shardSize = original[0].count

        // output recovery shards
        var recoveryPtrs = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: recoveryCount)
        for i in 0 ..< recoveryCount {
            recoveryPtrs[i] = UnsafeMutablePointer<UInt8>.allocate(capacity: shardSize)
            recoveryPtrs[i]?.initialize(repeating: 0, count: shardSize)
        }
        defer {
            for ptr in recoveryPtrs {
                ptr?.deallocate()
            }
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
    ///   - original: provide any original shards
    ///   - recovery: provide any recovery shards
    ///   - shardSize: size of each shard
    static func recover(
        originalCount: Int,
        recoveryCount: Int,
        original: [InnerShard],
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

        let originalOpaquePtrs = original.map(\.ptr.value)
        let recoveryOpaquePtrs = recovery.map(\.ptr.value)

        try FFIUtils.call { _ in
            originalOpaquePtrs.withUnsafeBufferPointer { originalBuffer in
                recoveryOpaquePtrs.withUnsafeBufferPointer { recoveryBuffer in
                    reed_solomon_recovery(
                        UInt(originalCount),
                        UInt(recoveryCount),
                        OpaquePointer(originalBuffer.baseAddress),
                        UInt(original.count),
                        OpaquePointer(recoveryBuffer.baseAddress),
                        UInt(recovery.count),
                        UInt(shardSize),
                        &originalPtrs
                    )
                }
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
    ///   - basicSize: The basic size of erasure-coded pieces in octets (should be 2 * number of cores; 684 for full config, aka `W_E`)
    ///   - recoveryCount: the number of recovery shards to create (should be the number of validators; 1023 for full config)
    /// - Returns: the list of smaller data chunks
    public static func chunk(data: Data, basicSize: Int, recoveryCount: Int) throws -> [Data] {
        var result: [Data] = []

        // data each of length k
        let unzipped = unzip(data: data, n: basicSize)

        var matrix: [[Data]] = []

        // TODO: may use concurrency to improve performance
        for original in unzipped {
            let originalShards = split(data: original, n: 2)
            let recoveryShards = try encode(original: originalShards, recoveryCount: recoveryCount)
            matrix.append(recoveryShards)
        }

        let transposed = transpose(matrix)

        for row in transposed {
            let joined = join(arr: row, n: 2)
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
        let keys = shards.map(\.index)
        let expectedKeys = Array(0 ..< UInt32(originalCount))
        if keys == expectedKeys {
            let sortedShards = shards.sorted { $0.index < $1.index }
            return sortedShards.compactMap(\.data).reduce(Data(), +)
        }

        let shardSize = shards[0].data.count
        let k = shardSize / 2

        var splitted = [(index: UInt32, data: [Data])]()
        for shard in shards {
            splitted.append((index: shard.index, data: split(data: shard.data, n: 2)))
        }

        var result = [Data](repeating: Data(), count: k)

        // TODO: may use concurrency to improve performance
        for p in 0 ..< k {
            var recoveryShards: [InnerShard] = []

            for (index, data) in splitted {
                try recoveryShards.append(.init(data: data[p], index: index))
            }

            let originalShards = try recover(
                originalCount: originalCount,
                recoveryCount: recoveryCount,
                original: [],
                recovery: recoveryShards,
                shardSize: 2
            )

            let originalData = join(arr: originalShards, n: 2)
            result[p] = originalData
        }

        return lace(arr: result, n: k)
    }
}
