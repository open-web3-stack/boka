import Utils

enum RequestError: Error {
    case null
    case notArray
    case unexpectedLength
}

public protocol RequestParameter: FromJSON {
    static var types: [Any.Type] { get }
}

extension VoidRequest: RequestParameter {
    public static var types: [Any.Type] { [] }
}

// Swift don't yet support variadic generics
// so we need to use this workaround

public struct Request1<T: FromJSON>: RequestParameter {
    public static var types: [Any.Type] { [T.self] }

    public let value: T

    public init(from json: JSON?) throws {
        guard let json else {
            throw RequestError.null
        }
        guard case let .array(arr) = json else {
            throw RequestError.notArray
        }
        guard arr.count <= 1 else {
            throw RequestError.unexpectedLength
        }
        value = try T(from: arr[safe: 0])
    }
}

public struct Request2<T1: FromJSON, T2: FromJSON>: RequestParameter {
    public static var types: [Any.Type] { [T1.self, T2.self] }

    public let value: (T1, T2)

    public init(from json: JSON?) throws {
        guard let json else {
            throw RequestError.null
        }
        guard case let .array(arr) = json else {
            throw RequestError.notArray
        }
        guard arr.count <= 2 else {
            throw RequestError.unexpectedLength
        }
        value = try (T1(from: arr[safe: 0]), T2(from: arr[safe: 1]))
    }
}

public struct Request3<T1: FromJSON, T2: FromJSON, T3: FromJSON>: RequestParameter {
    public static var types: [Any.Type] { [T1.self, T2.self, T3.self] }

    public let value: (T1, T2, T3)

    public init(from json: JSON?) throws {
        guard let json else {
            throw RequestError.null
        }
        guard case let .array(arr) = json else {
            throw RequestError.notArray
        }
        guard arr.count <= 3 else {
            throw RequestError.unexpectedLength
        }
        value = try (T1(from: arr[safe: 0]), T2(from: arr[safe: 1]), T3(from: arr[safe: 2]))
    }
}

public struct Request4<T1: FromJSON, T2: FromJSON, T3: FromJSON, T4: FromJSON>: RequestParameter {
    public static var types: [Any.Type] { [T1.self, T2.self, T3.self, T4.self] }

    public let value: (T1, T2, T3, T4)

    public init(from json: JSON?) throws {
        guard let json else {
            throw RequestError.null
        }
        guard case let .array(arr) = json else {
            throw RequestError.notArray
        }
        guard arr.count <= 4 else {
            throw RequestError.unexpectedLength
        }
        value = try (T1(from: arr[safe: 0]), T2(from: arr[safe: 1]), T3(from: arr[safe: 2]), T4(from: arr[safe: 3]))
    }
}
