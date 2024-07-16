import Foundation
import Testing

@testable import Utils

struct Data32Tests {
    @Test func testZero() throws {
        let value = Data32()
        #expect(value.data == Data(repeating: 0, count: 32))
        #expect(
            value.description
                == "0x0000000000000000000000000000000000000000000000000000000000000000"
        )
    }

    @Test func testInitWithData() throws {
        var data = Data(repeating: 0, count: 32)
        for i in 0 ..< 32 {
            data[i] = UInt8(i)
        }
        let value = Data32(data)!
        #expect(value.data == data)
        #expect(
            value.description
                == "0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        )
    }

    @Test func testInitWithInvalidData() throws {
        #expect(Data32(Data(repeating: 0, count: 31)) == nil)
        #expect(Data32(Data(repeating: 0, count: 33)) == nil)
    }

    @Test func testComparable() throws {
        let data1 = Data(repeating: 0, count: 32)
        var data2 = data1
        data2[31] = 1
        var data3 = data1
        data3[1] = 1

        let a = Data32(data1)!
        let b = Data32(data2)!
        let c = Data32(data3)!

        #expect(a < b)
        #expect(b < c)
        #expect(a < c)

        var arr = [c, b, a]
        arr.sort()
        #expect(arr == [a, b, c])
    }
}
