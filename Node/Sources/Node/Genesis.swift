import Blockchain
import Utils

public enum Genesis {
    case dev
    case file(path: String)
}

public extension Genesis {
    func toState() throws -> StateRef {
        switch self {
        case .file:
            fatalError("TODO: not implemented")
        case .dev:
            StateRef.dummy
        }
    }
}
