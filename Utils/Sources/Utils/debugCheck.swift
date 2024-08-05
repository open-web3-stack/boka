import Foundation

public enum AssertError: Error {
    case assertionFailed
}

public func debugCheck(
    _ condition: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line
) {
    #if DEBUG_ASSERT
        let res = Result { try condition() }
        switch res {
        case let .success(res):
            if !res {
                fatalError(file: file, line: line)
            }
        case let .failure(err):
            fatalError("\(err)", file: file, line: line)
        }
    #endif
}

public func debugCheck(
    _ condition: @autoclosure () async throws -> Bool, file: StaticString = #file,
    line: UInt = #line
) async {
    #if DEBUG_ASSERT
        let res = await Result { try await condition() }
        switch res {
        case let .success(res):
            if !res {
                fatalError(file: file, line: line)
            }
        case let .failure(err):
            fatalError("\(err)", file: file, line: line)
        }
    #endif
}
