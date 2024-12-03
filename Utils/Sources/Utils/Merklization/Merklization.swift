import Foundation

public enum Merklization {
    // roundup of half
    private static func half(_ i: Int) -> Int {
        (i + 1) / 2
    }

    private static func binaryMerklizeHelper<T, U>(
        _ nodes: T,
        hasher: Hashing.Type = Blake2b256.self
    ) -> MaybeEither<U, Data32>
        where T: RandomAccessCollection<U>, T.Index == Int, U: DataPtrRepresentable
    {
        switch nodes.count {
        case 0:
            return .init(right: Data32())
        case 1:
            return .init(left: nodes.first!)
        default:
            let midIndex = nodes.startIndex + half(nodes.count)
            let l = nodes[nodes.startIndex ..< midIndex]
            let r = nodes[midIndex ..< nodes.endIndex]

            return .init(right: hasher.hash("node", binaryMerklizeHelper(l).value, binaryMerklizeHelper(r).value))
        }
    }

    // well-balanced binary Merkle function defined in GP E.1.1
    public static func binaryMerklize<T: RandomAccessCollection<Data>>(_ nodes: T, hasher: Hashing.Type = Blake2b256.self) -> Data32
        where T.Index == Int
    {
        switch binaryMerklizeHelper(nodes, hasher: hasher).value {
        case let .left(data):
            hasher.hash(data)
        case let .right(data):
            data
        }
    }

    private static func traceImpl<T, U>(
        _ nodes: T,
        index: T.Index,
        hasher: Hashing.Type,
        output: (MaybeEither<U, Data32>) -> Void
    )
        where T: RandomAccessCollection<U>, T.Index == Int, U: DataPtrRepresentable
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

    public static func trace<T, U>(
        _ nodes: T,
        index: T.Index,
        hasher: Hashing.Type = Blake2b256.self
    ) -> [Either<U, Data32>]
        where T: RandomAccessCollection<U>, T.Index == Int, U: DataPtrRepresentable
    {
        var res: [Either<U, Data32>] = []
        traceImpl(nodes, index: index, hasher: hasher) { res.append($0.value) }
        return res
    }

    private static func constancyPreprocessor(
        _ nodes: some RandomAccessCollection<Data>,
        hasher: Hashing.Type = Blake2b256.self
    ) -> [Data32] {
        let length = UInt32(nodes.count)
        let newLength = Int(length.nextPowerOfTwo ?? 0)
        var res: [Data32] = []
        res.reserveCapacity(newLength)
        for node in nodes {
            res.append(hasher.hash("leaf", node))
        }
        // fill the rest with zeros
        for _ in nodes.count ..< newLength {
            res.append(Data32())
        }
        return res
    }

    // constant-depth binary merkle function defined in GP E.1.2
    public static func constantDepthMerklize<T: RandomAccessCollection<Data>>(_ nodes: T, hasher: Hashing.Type = Blake2b256.self) -> Data32
        where T.Index == Int
    {
        binaryMerklizeHelper(constancyPreprocessor(nodes, hasher: hasher)).unwrapped
    }

    public static func generateJustification<T>(
        _ nodes: T,
        index: T.Index,
        hasher: Hashing.Type = Blake2b256.self
    ) -> [Data32]
        where T: RandomAccessCollection<Data>, T.Index == Int
    {
        var res: [Data32] = []
        traceImpl(constancyPreprocessor(nodes, hasher: hasher), index: index, hasher: hasher) { res.append($0.unwrapped) }
        return res
    }
}
