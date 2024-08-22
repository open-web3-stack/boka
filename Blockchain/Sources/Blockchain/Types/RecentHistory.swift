import Utils

// β
public struct RecentHistory: Sendable, Equatable, Codable {
    public struct HistoryItem: Sendable, Equatable, Codable {
        // h
        public var headerHash: Data32

        // b: accumulation-result mmr
        public var mmrRoots: [Data32]

        // s
        public var stateRoot: Data32

        // p
        public var workReportHashes: ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.TotalNumberOfCores>

        public init(
            headerHash: Data32,
            mmrRoots: [Data32],
            stateRoot: Data32,
            workReportHashes: ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.TotalNumberOfCores>
        ) {
            self.headerHash = headerHash
            self.mmrRoots = mmrRoots
            self.stateRoot = stateRoot
            self.workReportHashes = workReportHashes
        }
    }

    public var blocks: ConfigLimitedSizeArray<HistoryItem, ProtocolConfig.Int0, ProtocolConfig.RecentHistorySize>
}

extension RecentHistory: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> RecentHistory {
        RecentHistory(blocks: try! ConfigLimitedSizeArray(config: config))
    }
}
