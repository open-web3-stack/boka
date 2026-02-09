import Codec
import TracingUtils
import Utils

private let logger = Logger(label: "RecentHistory")

/// β
public struct RecentHistory: Sendable, Equatable, Codable {
    public struct HistoryItem: Sendable, Equatable, Codable {
        /// h
        public var headerHash: Data32

        /// b
        public var superPeak: Data32

        /// s
        public var stateRoot: Data32

        // p: work package hash -> segment root lookup
        @CodingAs<SortedKeyValues<Data32, Data32>> public var lookup: [Data32: Data32]

        public init(
            headerHash: Data32,
            superPeak: Data32,
            stateRoot: Data32,
            lookup: [Data32: Data32],
        ) {
            self.headerHash = headerHash
            self.superPeak = superPeak
            self.stateRoot = stateRoot
            self.lookup = lookup
        }
    }

    /// H
    public var items: ConfigLimitedSizeArray<HistoryItem, ProtocolConfig.Int0, ProtocolConfig.RecentHistorySize>

    // B: Accumulation Output Log
    public var mmr: MMR
}

extension RecentHistory: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> RecentHistory {
        RecentHistory(
            items: try! ConfigLimitedSizeArray(
                config: config,
                array: [HistoryItem(
                    headerHash: Data32(),
                    superPeak: Data32(),
                    stateRoot: Data32(),
                    lookup: [Data32: Data32](),
                )],
            ),
            mmr: MMR([]),
        )
    }
}

extension RecentHistory {
    public mutating func updatePartial(
        parentStateRoot: Data32,
    ) {
        if items.count > 0 { // if this is not block #0
            // write the state root of last block
            items[items.endIndex - 1].stateRoot = parentStateRoot
        }
    }

    public mutating func update(
        headerHash: Data32,
        accumulateRoot: Data32,
        lookup: [Data32: Data32],
    ) {
        mmr.append(accumulateRoot, hasher: Keccak.self)

        logger.debug("recent history new item mmr: \(mmr)")

        let newItem = RecentHistory.HistoryItem(
            headerHash: headerHash,
            superPeak: mmr.superPeak(),
            stateRoot: Data32(), // empty and will be updated upon next block
            lookup: lookup,
        )

        items.safeAppend(newItem)
    }
}
