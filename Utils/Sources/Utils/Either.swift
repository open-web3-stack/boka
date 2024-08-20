public enum Either<A, B>: Codable where A: Codable, B: Codable {
    case left(A)
    case right(B)
}

extension Either: Equatable where A: Equatable, B: Equatable {}

extension Either: Sendable where A: Sendable, B: Sendable {}

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
