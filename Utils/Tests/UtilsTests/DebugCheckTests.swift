import Foundation
import Testing

@testable import Utils

struct DebugCheckTests {
    func awaitThrow(_ expression: () async throws -> some Any) async throws -> Bool {
        _ = try await expression()
        return true
    }

    func doesThrow(_ expression: () throws -> some Any) throws -> Bool {
        _ = try expression()
        return true
    }

    @Test
    func testDebugCheck() async throws {
        #if DEBUG_ASSERT
            try #expect(doesThrow {
                try debugCheck(1 + 1 == 2)
            } == true)
            #expect(throws: DebugCheckError.self) {
                try debugCheck(1 + 1 == 3)
            }
            try await #expect(awaitThrow {
                try await debugCheck(1 + 1 == 2)
            } == true)

            await #expect(throws: DebugCheckError.self) {
                try await debugCheck(1 + 1 == 3)
            }
        #else
            try await debugCheck(1 + 1 == 2) // Should not throw
            try await debugCheck(1 + 1 == 3) // Should not throw
            try await debugCheck(1 + 1 == 2) // Should not throw
            try await debugCheck(1 + 1 == 3) // Should not throw
        #endif
    }
}
