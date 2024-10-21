import Utils

// β
public struct RecentHistory: Sendable, Equatable, Codable {
    public struct HistoryItem: Sendable, Equatable, Codable {
        // h
        public var headerHash: Data32

        // b: accumulation-result mmr
        public var mmr: MMR

        // s
        public var stateRoot: Data32

        // p
        public var workReportHashes: ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.TotalNumberOfCores>

        public init(
            headerHash: Data32,
            mmr: MMR,
            stateRoot: Data32,
            workReportHashes: ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.TotalNumberOfCores>
        ) {
            self.headerHash = headerHash
            self.mmr = mmr
            self.stateRoot = stateRoot
            self.workReportHashes = workReportHashes
        }
    }

    public var items: ConfigLimitedSizeArray<HistoryItem, ProtocolConfig.Int0, ProtocolConfig.RecentHistorySize>
}

extension RecentHistory: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> RecentHistory {
        RecentHistory(items: try! ConfigLimitedSizeArray(
            config: config,
            array: [HistoryItem(
                headerHash: Data32(),
                mmr: MMR([]),
                stateRoot: Data32(),
                workReportHashes: ConfigLimitedSizeArray(config: config)
            )]
        ))
    }
}

extension RecentHistory {
    public mutating func update(
        headerHash: Data32,
        parentStateRoot: Data32,
        accumulateRoot: Data32,
        workReportHashes: ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.TotalNumberOfCores>
    ) {
        if items.count > 0 { // if this is not block #0
            // write the state root of last block
            items[items.endIndex - 1].stateRoot = parentStateRoot
        }

        var mmr = items.last?.mmr ?? .init([])
        mmr.append(accumulateRoot, hasher: Keccak.self)

        let newItem = RecentHistory.HistoryItem(
            headerHash: headerHash,
            mmr: mmr,
            stateRoot: Data32(), // empty and will be updated upon next block
            workReportHashes: workReportHashes
        )

        items.safeAppend(newItem)
    }
}
