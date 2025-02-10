import Foundation

public enum DebugCheckError: Error {
    case assertionFailed(String, file: StaticString, line: UInt)
    case unexpectedError(Error, file: StaticString, line: UInt)
}

public func debugCheck(
    _ condition: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line
) throws {
    #if DEBUG_ASSERT
    let result = Result { try condition() }
    switch result {
    case let .success(isValid):
        if !isValid {
            throw DebugCheckError.assertionFailed("Assertion failed", file: file, line: line)
        }
    case let .failure(error):
        throw DebugCheckError.unexpectedError(error, file: file, line: line)
    }
    #endif
}

public func debugCheck(
    _ condition: @autoclosure () async throws -> Bool, file: StaticString = #file, line: UInt = #line
) async throws {
    #if DEBUG_ASSERT
    let result = await Result { try await condition() }
    switch result {
    case let .success(isValid):
        if !isValid {
            throw DebugCheckError.assertionFailed("Assertion failed", file: file, line: line)
        }
    case let .failure(error):
        throw DebugCheckError.unexpectedError(error, file: file, line: line)
    }
    #endif
}
