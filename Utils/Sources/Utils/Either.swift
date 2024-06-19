import ScaleCodec

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

extension Either: ScaleCodec.Codable where A: ScaleCodec.Codable, B: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        let id = try decoder.decode(.enumCaseId)
        switch id {
        case 0:
            self = try .left(A(from: &decoder))
        case 1:
            self = try .right(B(from: &decoder))
        default:
            throw decoder.enumCaseError(for: id)
        }
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        switch self {
        case let .left(a):
            try encoder.encode(0, .enumCaseId)
            try a.encode(in: &encoder)
        case let .right(b):
            try encoder.encode(1, .enumCaseId)
            try b.encode(in: &encoder)
        }
    }
}
