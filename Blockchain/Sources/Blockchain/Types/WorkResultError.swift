public enum WorkResultError1: Error, CaseIterable {
    case outofGas
    case panic
    case invalidCode
    case codeTooLarge // code larger than MaxServiceCodeSize
}

extension WorkResultError1: Codable {
    enum CodingKeys: String, CodingKey {
        case outofGas
        case panic
        case invalidCode
        case codeTooLarge
    }

    public init(from decoder: Decoder) throws {
        if decoder.isJamCodec {
            let variant = try decoder.singleValueContainer().decode(UInt8.self)
            switch variant {
            case 0:
                self = .outofGas
            case 1:
                self = .panic
            case 2:
                self = .invalidCode
            case 3:
                self = .codeTooLarge
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid WorkResultError: unknown variant \(variant)"
                    )
                )
            }
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.outofGas) {
                self = .outofGas
            } else if container.contains(.panic) {
                self = .panic
            } else if container.contains(.invalidCode) {
                self = .invalidCode
            } else if container.contains(.codeTooLarge) {
                self = .codeTooLarge
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Invalid WorkResultError: must contain either outofGas or panic"
                    )
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        if encoder.isJamCodec {
            var container = encoder.unkeyedContainer()
            switch self {
            case .outofGas:
                try container.encode(0)
            case .panic:
                try container.encode(1)
            case .invalidCode:
                try container.encode(2)
            case .codeTooLarge:
                try container.encode(3)
            }
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .outofGas:
                try container.encodeNil(forKey: .outofGas)
            case .panic:
                try container.encodeNil(forKey: .panic)
            case .invalidCode:
                try container.encodeNil(forKey: .invalidCode)
            case .codeTooLarge:
                try container.encodeNil(forKey: .codeTooLarge)
            }
        }
    }
}
