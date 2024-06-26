import Blockchain
import Utils

public enum Genesis {
    case dev
    case file(path: String)
}

extension Genesis {
    public func toState(withConfig config: ProtocolConfigRef) throws -> StateRef {
        switch self {
        case .file:
            fatalError("TODO: not implemented")
        case .dev:
            StateRef.dummy(withConfig: config)
        }
    }
}
