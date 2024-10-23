import Codec

public enum Either<Left, Right> {
    case left(Left)
    case right(Right)

    public var left: Left? {
        if case let .left(left) = self {
            return left
        }
        return nil
    }

    public var right: Right? {
        if case let .right(right) = self {
            return right
        }
        return nil
    }
}

extension Either: Equatable where Left: Equatable, Right: Equatable {}

extension Either: Sendable where Left: Sendable, Right: Sendable {}

extension Either: CustomStringConvertible where Left: CustomStringConvertible, Right: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .left(a):
            "Left(\(a))"
        case let .right(b):
            "Right(\(b))"
        }
    }
}

extension Either: Codable where Left: Codable, Right: Codable {
    enum CodingKeys: String, CodingKey {
        case left
        case right
    }

    public func encode(to encoder: Encoder) throws {
        if encoder.isJamCodec {
            var container = encoder.unkeyedContainer()
            switch self {
            case let .left(a):
                try container.encode(0)
                try container.encode(a)
            case let .right(b):
                try container.encode(1)
                try container.encode(b)
            }
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .left(a):
                try container.encode(a, forKey: .left)
            case let .right(b):
                try container.encode(b, forKey: .right)
            }
        }
    }

    public init(from decoder: Decoder) throws {
        if decoder.isJamCodec {
            var container = try decoder.unkeyedContainer()
            let variant = try container.decode(UInt8.self)
            switch variant {
            case 0:
                let a = try container.decode(Left.self)
                self = .left(a)
            case 1:
                let b = try container.decode(Right.self)
                self = .right(b)
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid Either: unknown variant \(variant)"
                    )
                )
            }
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.left) {
                let a = try container.decode(Left.self, forKey: .left)
                self = .left(a)
            } else if container.contains(.right) {
                let b = try container.decode(Right.self, forKey: .right)
                self = .right(b)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Invalid Either: must contain either left or right"
                    )
                )
            }
        }
    }
}

extension Either: EncodedSize where Left: EncodedSize, Right: EncodedSize {
    public var encodedSize: Int {
        switch self {
        case let .left(left):
            left.encodedSize + 1
        case let .right(right):
            right.encodedSize + 1
        }
    }

    public static var encodeedSizeHint: Int? {
        if let left = Left.encodeedSizeHint, let right = Right.encodeedSizeHint {
            return left + right + 1
        }
        return nil
    }
}
