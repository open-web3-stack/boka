import Blockchain
import Utils

public enum Genesis {
    case dev
    case file(path: String)
}

extension Genesis {
    public func toState(config: ProtocolConfigRef) throws -> StateRef {
        switch self {
        case .file:
            fatalError("TODO: not implemented")
        case .dev:
            StateRef.dummy(config: config)
        }
    }
}
