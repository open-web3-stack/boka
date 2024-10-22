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
