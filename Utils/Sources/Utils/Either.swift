public enum Either<A, B> {
    case left(A)
    case right(B)
}

extension Either: Equatable where A: Equatable, B: Equatable {}

extension Either: CustomStringConvertible where A: CustomStringConvertible, B: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .left(a):
            "Left(\(a))"
        case let .right(b):
            "Right(\(b))"
        }
    }
}
