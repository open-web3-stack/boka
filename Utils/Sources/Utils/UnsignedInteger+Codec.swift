import Foundation

struct IntegerEncoder<T: UnsignedInteger>: Sequence {
    public typealias Element = UInt8

    private var value: T
    private let method: EncodeMethod

    public init(value: T, method: EncodeMethod) {
        self.value = value
        self.method = method
    }

    public func makeIterator() -> Iterator {
        Iterator(value: value, method: method)
    }

    struct Iterator: IteratorProtocol {
        let method: EncodeMethod
        let value: T
        var position: Int
        var length: Int?

        init(value: T, method: EncodeMethod) {
            self.value = value
            self.method = method
            position = 0
        }

        public mutating func next() -> UInt8? {
            defer { position += 1 }
            switch method {
            case let .fixedWidth(width):
                guard position < width else {
                    return nil
                }
                let byte = UInt8(value >> (position * 8) & 0xFF)
                return byte
            case .variableWidth:
                if value == 0 {
                    return position == 0 ? 0 : nil
                }
                if position == 0 {
                    for l in 0 ..< 8 where value < (1 << (7 * (l + 1))) {
                        length = l
                        let prefix = UInt8(256 - 1 << (8 - l))
                        let data = UInt8(value / (1 << (8 * l)))
                        return prefix + data
                    }
                    length = 8
                    return 255
                }
                guard let length else {
                    assertionFailure("length is not set. this should not be possible")
                    return nil
                }

                guard position <= length else {
                    return nil
                }

                let byte = UInt8(value >> ((position - 1) * 8) & 0xFF)
                return byte
            }
        }
    }
}

public enum EncodeMethod: Sendable {
    case fixedWidth(Int)
    case variableWidth
}

extension UnsignedInteger {
    public func encode(method: EncodeMethod) -> some Sequence<UInt8> {
        IntegerEncoder(value: self, method: method)
    }
}
