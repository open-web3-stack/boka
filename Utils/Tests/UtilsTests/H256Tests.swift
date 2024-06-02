import XCTest
@testable import Utils

final class H256Tests: XCTestCase {
    func testZero() throws {
        let value = H256.zero
        XCTAssertEqual(value.data, Data(repeating: 0, count: 32))
        XCTAssertEqual(value.description, "0x0000000000000000000000000000000000000000000000000000000000000000")
    }
    
    func testInitWithData() throws {
        var data = Data(repeating: 0, count: 32)
        for i in 0..<32 {
            data[i] = UInt8(i)
        }
        let value = H256(data)!
        XCTAssertEqual(value.data, data)
        XCTAssertEqual(value.description, "0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    }

    func testInitWithInvalidData() throws {
        XCTAssertNil(H256(Data(repeating: 0, count: 31)))
        XCTAssertNil(H256(Data(repeating: 0, count: 33)))
    }
}
