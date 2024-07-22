import Foundation
import Testing
import Utils

@testable import PolkaVM

struct ProgramTests {
    @Test func empty() {
        let blob = Data()
        #expect(throws: ProgramCode.Error.invalidJumpTableEntriesCount) { try ProgramCode(blob) }
    }

    @Test func invalidJumpTableEntriesCount() {
        let highValue = Data(UInt64(0x1000000).encode(method: .variableWidth))
        let data = highValue + Data([0, 0])
        #expect(throws: ProgramCode.Error.invalidJumpTableEntriesCount) { try ProgramCode(data) }
    }

    @Test func invalidJumpTableEncodeSize() {
        let data = Data([1, 0xFF, 0, 0])
        #expect(throws: ProgramCode.Error.invalidJumpTableEncodeSize) { try ProgramCode(data) }
    }

    @Test func invalidCodeLength() {
        let highValue = Data(UInt64(0x1000000).encode(method: .variableWidth))
        let data = Data([0, 0]) + highValue
        #expect(throws: ProgramCode.Error.invalidCodeLength) { try ProgramCode(data) }
    }

    @Test func tooMuchData() throws {
        let data = Data([0, 0, 2, 1, 2, 0, 0])
        #expect(throws: ProgramCode.Error.invalidDataLength) { try ProgramCode(data) }
    }

    @Test func tooLittleData() throws {
        let data = Data([0, 0, 2, 1, 2])
        #expect(throws: ProgramCode.Error.invalidDataLength) { try ProgramCode(data) }
    }

    @Test func minimal() throws {
        let data = Data([0, 0, 0])
        _ = try ProgramCode(data)
    }

    @Test func simple() throws {
        let data = Data([0, 0, 2, 1, 2, 0])
        _ = try ProgramCode(data)
    }

    // TODO: add more Program parsing tests

    @Test(arguments: [
        (Data(), 0, nil),
        (Data([0]), 0, 24),
        (Data([0]), 8, nil),
        (Data([0b0010_0000]), 0, 4),
        (Data([0b0010_0000]), 3, 1),
        (Data([0b0010_0000]), 6, 24),
        (Data([0b0010_0000]), 7, nil),
        (Data([0, 0, 0b0010_0000, 0b0000_0010]), 0, 20),
        (Data([0, 0, 0b0010_0000, 0b0000_0010]), 2, 18),
        (Data([0, 0, 0b0010_0000, 0b0000_0010]), 10, 10),
        (Data([0, 0, 0b0010_0000, 0b0000_0010]), 22, 2),
        (Data([0, 0, 0, 0b0000_0010]), 5, 19),
    ] as[(Data, UInt, UInt?)])
    func skip(testCase: (Data, UInt, UInt?)) {
        #expect(ProgramCode.skipOffset(start: testCase.1, bitmask: testCase.0) == testCase.2)
    }
}
