import TracingUtils
import Utils

private let logger = Logger(label: "StateRef")

public final class StateRef: Ref<State>, @unchecked Sendable {
    public required init(_ value: State) {
        lazyStateRoot = Lazy {
            do {
                return try Ref(value.stateRoot())
            } catch {
                logger.warning("stateRoot() failed, using empty hash", metadata: ["error": "\(error)"])
                return Ref(Data32())
            }
        }

        super.init(value)
    }

    private let lazyStateRoot: Lazy<Ref<Data32>>

    public var stateRoot: Data32 {
        lazyStateRoot.value.value
    }

    override public var description: String {
        "StateRef(\(stateRoot.toHexString()))"
    }
}

extension StateRef: Codable {
    public convenience init(from decoder: Decoder) throws {
        try self.init(.init(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

extension StateRef {
    public static func dummy(config: ProtocolConfigRef, block: BlockRef) -> StateRef {
        dummy(config: config).mutate {
            $0.recentHistory.items.safeAppend(RecentHistory.HistoryItem(
                headerHash: block.hash,
                mmr: MMR([]),
                stateRoot: Data32(),
                workReportHashes: try! ConfigLimitedSizeArray(config: config)
            ))
            $0.timeslot = block.header.timeslot + 1
        }
    }
}
