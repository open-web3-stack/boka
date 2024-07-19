import Foundation
import Testing
import Utils

@testable import PolkaVM

struct ProgramTests {
    @Test func empty() {
        let blob = Data()
        #expect(throws: Program.Error.invalidJumpTableEntriesCount) { try Program(blob) }
    }

    @Test func invalidJumpTableEntriesCount() {
        let highValue = Data(UInt64(0x1000000).encode(method: .variableWidth))
        let data = highValue + Data([0, 0])
        #expect(throws: Program.Error.invalidJumpTableEntriesCount) { try Program(data) }
    }

    @Test func invalidJumpTableEncodeSize() {
        let data = Data([1, 0xFF, 0, 0])
        #expect(throws: Program.Error.invalidJumpTableEncodeSize) { try Program(data) }
    }

    @Test func minimal() throws {
        let data = Data([0, 0, 0])
        _ = try Program(data)
    }
}
