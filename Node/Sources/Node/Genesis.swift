import Blockchain
import Utils

public enum Genesis {
    case dev
    case file(path: String)
}

extension Genesis {
    public func load() async throws -> (StateRef, ProtocolConfigRef) {
        switch self {
        case .file:
            fatalError("TODO: not implemented")
        case .dev:
            let config = ProtocolConfigRef.dev
            let state = try State.devGenesis(config: config)

            return (StateRef(state), config)
        }
    }
}
