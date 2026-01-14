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
        case invalidShardIndex(UInt32)
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
    static func join(arr: [Data]) -> Data {
        var result = Data(capacity: arr.count * arr[0].count)

        for d in arr {
            result.append(d)
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

    /// C: encode original shards into a systematic codeword of length `recoveryCount`
    static func encode(original: [Data], recoveryCount: Int) throws -> [Data] {
        guard !original.isEmpty else { return [] }

        let originalCount = original.count
        let shardSize = original[0].count
        guard recoveryCount >= originalCount else { throw Error.invalidShardsCount }

        let parityCount = recoveryCount - originalCount
        if parityCount == 0 {
            return original
        }

        var originalBuffers: [UnsafeMutableBufferPointer<UInt8>] = []
        originalBuffers.reserveCapacity(originalCount)
        for shard in original {
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: shardSize)
            _ = buffer.initialize(from: shard)
            originalBuffers.append(buffer)
        }

        var recoveryBuffers: [UnsafeMutableBufferPointer<UInt8>] = []
        recoveryBuffers.reserveCapacity(parityCount)
        for _ in 0 ..< parityCount {
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

        let originalPtrs: [UnsafePointer<UInt8>?] = originalBuffers.map { UnsafePointer<UInt8>($0.baseAddress) }
        var recoveryPtrs: [UnsafeMutablePointer<UInt8>?] = recoveryBuffers.map(\.baseAddress)

        let ret = originalPtrs.withUnsafeBufferPointer { originalBuffer in
            recoveryPtrs.withUnsafeMutableBufferPointer { recoveryBuffer in
                reed_solomon_encode(
                    originalBuffer.baseAddress,
                    UInt(originalCount),
                    UInt(recoveryCount), // FFI expects total shard count, not just parity
                    UInt(shardSize),
                    recoveryBuffer.baseAddress
                )
            }
        }
        if ret != 0 { throw Error.encodeFailed(Int(ret)) }

        var parity = [Data]()
        for i in 0 ..< parityCount {
            let data = Data(bytes: recoveryBuffers[i].baseAddress!, count: shardSize)
            parity.append(data)
        }

        return original + parity
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
        guard recoveryCount >= originalCount else { throw Error.invalidShardsCount }
        let parityCount = recoveryCount - originalCount

        var originalShards: [InnerShard] = []
        var parityShards: [InnerShard] = []

        for shard in recovery {
            guard let rawIndex = shard.index else {
                throw Error.getIndexFailed(-1)
            }

            guard let data = shard.data else {
                throw Error.getDataFailed(-1)
            }

            if rawIndex < UInt32(originalCount) {
                try originalShards.append(InnerShard(data: data, index: rawIndex))
                continue
            }

            // Parity shard: use absolute index (not relative)
            // FFI expects absolute indices: 0..(originalCount-1) for original,
            // originalCount..(recoveryCount-1) for parity
            guard rawIndex < UInt32(recoveryCount) else {
                throw Error.invalidShardIndex(rawIndex)
            }

            try parityShards.append(InnerShard(data: data, index: rawIndex))
        }

        // output original shards
        var originalPtrs: [UnsafeMutablePointer<UInt8>?] = []
        originalPtrs.reserveCapacity(originalCount)
        for _ in 0 ..< originalCount {
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: shardSize)
            ptr.initialize(repeating: 0, count: shardSize)
            originalPtrs.append(ptr)
        }

        defer {
            for ptr in originalPtrs {
                ptr?.deallocate()
            }
        }

        // use arrays of OpaquePointer directly without copying SafePointer
        var originalOpaquePtrs = [OpaquePointer?](repeating: nil, count: originalShards.count)
        for (i, shard) in originalShards.enumerated() {
            originalOpaquePtrs[i] = shard.ptr.value
        }

        // Prefill known original shards so the output contains provided data even if FFI does not write it back.
        for shard in originalShards {
            guard
                let idx = shard.index,
                let data = shard.data,
                idx < UInt32(originalCount)
            else { continue }

            data.copyBytes(to: originalPtrs[Int(idx)]!, count: min(data.count, shardSize))
        }

        var recoveryOpaquePtrs = [OpaquePointer?](repeating: nil, count: parityShards.count)

        for (i, shard) in parityShards.enumerated() {
            recoveryOpaquePtrs[i] = shard.ptr.value
        }

        let ret = originalOpaquePtrs.withUnsafeBufferPointer { originalBuffer in
            recoveryOpaquePtrs.withUnsafeBufferPointer { recoveryBuffer in
                originalPtrs.withUnsafeMutableBufferPointer { outputBuffer in
                    reed_solomon_recovery(
                        UInt(originalCount),
                        UInt(recoveryCount), // FFI expects total shard count, not just parity
                        originalBuffer.baseAddress,
                        UInt(originalOpaquePtrs.count),
                        recoveryBuffer.baseAddress,
                        UInt(recoveryOpaquePtrs.count),
                        UInt(shardSize),
                        outputBuffer.baseAddress
                    )
                }
            }
        }
        if ret != 0 {
            throw Error.recoveryFailed(Int(ret))
        }

        var recoveredShards = [Data](repeating: Data(), count: originalCount)
        for i in 0 ..< originalCount {
            if let ptr = originalPtrs[i] {
                recoveredShards[i] = Data(bytes: ptr, count: shardSize)
            }
        }

        return recoveredShards
    }

    /// C_k: erasure-code chunking function (eq H.4)
    /// - Parameters:
    ///   - data: the original data
    ///   - basicSize: ≈ 2 * number of cores; W_E (erasureCodedPieceSize), 684 for full config
    ///   - recoveryCount: ≈ number of validators; 1023 for full config
    /// - Returns: the list of smaller data chunks
    public static func chunk(data: Data, basicSize: Int, recoveryCount: Int) throws -> [Data] {
        guard basicSize % 2 == 0 else { throw Error.invalidBasicSize(basicSize) }
        guard !data.isEmpty else { return [] }

        let k = (data.count + basicSize - 1) / basicSize
        let paddedLength = k * basicSize
        var padded = data
        if padded.count < paddedLength {
            padded.append(contentsOf: repeatElement(0, count: paddedLength - padded.count))
        }

        let splitted = split(data: padded, n: 2 * k)

        let splitted2 = splitted.map { split(data: $0, n: Constants.INNER_SHARD_SIZE) }

        let originalShards = transpose(splitted2)

        var result2d: [[Data]] = []

        for original in originalShards {
            let codeword = try encode(original: original, recoveryCount: recoveryCount)
            result2d.append(codeword)
        }

        let transposed = transpose(result2d)

        return transposed.map { join(arr: $0) }
    }

    /// R_k: erasure-code reconstruction function (eq H.5)
    /// - Parameters:
    ///   - shards: the shards to reconstruct the original data, should be ordered
    ///   - basicSize: ≈ 2 * number of cores; 684 for full config
    ///   - originalCount: the total number of original items
    ///   - recoveryCount: the total number of recovery items
    ///   - originalLength: optional original data length, used to drop padding when known
    /// - Returns: the reconstructed original data
    public static func reconstruct(
        shards: [Shard],
        basicSize: Int,
        originalCount: Int,
        recoveryCount: Int,
        originalLength: Int? = nil
    ) throws -> Data {
        guard !shards.isEmpty else { return Data() }
        guard basicSize % 2 == 0 else { throw Error.invalidBasicSize(basicSize) }
        guard shards.count >= originalCount else { throw Error.invalidShardsCount }

        // Fast path: all original shards are available
        let originalMap = Dictionary(uniqueKeysWithValues: shards.map { (Int($0.index), $0.data) })
        let availableOriginals = (0 ..< originalCount).compactMap { originalMap[$0] }
        if availableOriginals.count == originalCount {
            let reconstructed = join(arr: availableOriginals)
            if let originalLength {
                return reconstructed.prefix(originalLength)
            }
            return reconstructed
        }

        let shardSize = shards[0].data.count
        let k = (shardSize + Constants.INNER_SHARD_SIZE - 1) / Constants.INNER_SHARD_SIZE

        let splitted = shards.map { split(data: $0.data, n: Constants.INNER_SHARD_SIZE) }

        var result2d: [[Data]] = []

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

            result2d.append(originalShards)
        }

        let transposed = transpose(result2d)

        let reconstructed = join(arr: transposed.map { join(arr: $0) })
        if let originalLength {
            return reconstructed.prefix(originalLength)
        }
        return reconstructed
    }
}
