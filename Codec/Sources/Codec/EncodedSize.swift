import Foundation

public protocol EncodedSize {
    var encodedSize: Int { get }

    static var encodeedSizeHint: Int? { get }
}

extension FixedWidthInteger {
    public var encodedSize: Int {
        MemoryLayout<Self>.size
    }

    public static var encodeedSizeHint: Int? {
        MemoryLayout<Self>.size
    }
}

extension Bool: EncodedSize {
    public var encodedSize: Int {
        1
    }

    public static var encodeedSizeHint: Int? {
        1
    }
}

extension String: EncodedSize {
    public var encodedSize: Int {
        utf8.count
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension Data: EncodedSize {
    public var encodedSize: Int {
        UInt32(count).variableEncodingLength() + count
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension Array: EncodedSize where Element: EncodedSize {
    public var encodedSize: Int {
        let prefixSize = UInt32(count).variableEncodingLength()
        if let hint = Element.encodeedSizeHint {
            return prefixSize + hint * count
        }
        return reduce(into: prefixSize) { $0 += $1.encodedSize }
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension Optional: EncodedSize where Wrapped: EncodedSize {
    public var encodedSize: Int {
        switch self {
        case let .some(wrapped):
            wrapped.encodedSize + 1
        case .none:
            1
        }
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension Result: EncodedSize where Success: EncodedSize, Failure: EncodedSize {
    public var encodedSize: Int {
        switch self {
        case let .success(success):
            success.encodedSize + 1
        case let .failure(failure):
            failure.encodedSize + 1
        }
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension Set: EncodedSize where Element: EncodedSize {
    public var encodedSize: Int {
        reduce(into: UInt32(count).variableEncodingLength()) { $0 += $1.encodedSize }
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension Dictionary: EncodedSize where Key: EncodedSize, Value: EncodedSize {
    public var encodedSize: Int {
        reduce(into: UInt32(count).variableEncodingLength()) { $0 += $1.key.encodedSize + $1.value.encodedSize }
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}
