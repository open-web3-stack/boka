import Blockchain
import Utils

public enum Genesis {
    case dev
    case file(path: String)
}

public extension Genesis {
    func toState() -> StateRef {
        switch self {
        case .file:
            fatalError("TODO: not implemented")
        case .dev:
            fatalError("TODO: not implemented")
        }
    }
}
