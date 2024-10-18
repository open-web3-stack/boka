import Logging

let logger = Logger(label: "tracing-utils.assertions")

public enum AssertionError: Error {
    case unreachable(String)
}

public func throwUnreachable(_ msg: String, file: String = #fileID, function: String = #function, line: UInt = #line) throws -> Never {
    unreachable(msg, file: file, function: function, line: line)
    throw AssertionError.unreachable(msg)
}

public func unreachable(_ msg: String, file: String = #fileID, function: String = #function, line: UInt = #line) {
    logger.error("unreachable: \(msg)", metadata: nil, source: nil, file: file, function: function, line: line)
    assertionFailure(msg)
}
