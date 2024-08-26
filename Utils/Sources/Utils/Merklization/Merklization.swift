import Foundation

// TODO: add tests
public enum Merklization {
    // roundup of half
    private static func half(_ i: Int) -> Int {
        (i + 1) / 2
    }

    private static func binaryMerklizeHelper<T: RandomAccessCollection<Data>>(_ nodes: T,
                                                                              hasher: Hashing.Type = Blake2b256
                                                                                  .self) -> Either<Data, Data32>
        where T.Index == Int
    {
        switch nodes.count {
        case 0:
            return .right(Data32())
        case 1:
            return .left(nodes.first!)
        default:
            let midIndex = nodes.startIndex + half(nodes.count)
            let l = nodes[nodes.startIndex ..< midIndex]
            let r = nodes[midIndex ..< nodes.endIndex]
            var hash = hasher.init()
            hash.update("node")
            hash.update(binaryMerklizeHelper(l))
            hash.update(binaryMerklizeHelper(r))
            return .right(hash.finalize())
        }
    }

    // well-balanced binary Merkle function defined in GP E.1.1
    public static func binaryMerklize<T: RandomAccessCollection<Data>>(_ nodes: T, hasher: Hashing.Type = Blake2b256.self) -> Data32
        where T.Index == Int
    {
        switch binaryMerklizeHelper(nodes, hasher: hasher) {
        case let .left(data):
            hasher.hash(data: data)
        case let .right(data):
            data
        }
    }

    private static func traceImpl<T: RandomAccessCollection<Data>>(_ nodes: T, index: T.Index,
                                                                   hasher: Hashing.Type, output: (Either<Data, Data32>) -> Void)
        where T.Index == Int
    {
        if nodes.count == 0 {
            return
        }

        func selectPart(left: Bool, nodes: T, index: T.Index) -> T.SubSequence {
            let h = half(nodes.count)
            if (index < h) == left {
                return nodes[nodes.startIndex ..< nodes.startIndex + h]
            } else {
                return nodes[nodes.startIndex + h ..< nodes.endIndex]
            }
        }

        func selectIndex(nodes: T, index: T.Index) -> T.Index {
            let h = half(nodes.count)
            if index < h {
                return 0
            }
            return h
        }

        let l = binaryMerklizeHelper(selectPart(left: true, nodes: nodes, index: index), hasher: hasher)
        output(l)
        traceImpl(
            selectPart(left: false, nodes: nodes, index: index),
            index: index - selectIndex(nodes: nodes, index: index),
            hasher: hasher,
            output: output
        )
    }

    public static func trace<T: RandomAccessCollection<Data>>(_ nodes: T, hasher: Hashing.Type = Blake2b256.self) -> [Either<Data, Data32>]
        where T.Index == Int
    {
        var res: [Either<Data, Data32>] = []
        traceImpl(nodes, index: nodes.count, hasher: hasher) { res.append($0) }
        return res
    }

    // return type should be [Data32] but binaryMerklizeHelper requires [Data]
    private static func constancyPreprocessor(_ nodes: some RandomAccessCollection<Data>,
                                              hasher: Hashing.Type = Blake2b256.self) -> [Data]
    {
        let length = UInt32(nodes.count)
        // find the next power of two using bitwise logic
        let nextPowerOfTwo = UInt32(1 << (32 - length.leadingZeroBitCount))
        let newLength = Int(nextPowerOfTwo == length ? length : nextPowerOfTwo * 2)
        var res: [Data] = []
        res.reserveCapacity(newLength)
        for node in nodes {
            var hash = hasher.init()
            hash.update("leaf")
            hash.update(node)
            res.append(hash.finalize().data)
        }
        // fill the rest with zeros
        for _ in nodes.count ..< newLength {
            res.append(Data32().data)
        }
        return res
    }

    // constant-depth binary merkle function defined in GP E.1.2
    public static func constantDepthMerklize<T: RandomAccessCollection<Data>>(_ nodes: T, hasher: Hashing.Type = Blake2b256.self) -> Data32
        where T.Index == Int
    {
        switch binaryMerklizeHelper(constancyPreprocessor(nodes, hasher: hasher)) {
        case let .left(data):
            Data32(data)! // TODO: somehow improve the typing so force unwrap is not needed
        case let .right(data):
            data
        }
    }
}
