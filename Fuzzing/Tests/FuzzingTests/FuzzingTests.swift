import Foundation
import Testing

@testable import Fuzzing

struct FuzzingTests {
    @Test func testSeededRandomNumberGenerator() throws {
        let seed: UInt64 = 42
        let generator1 = SeededRandomNumberGenerator(seed: seed)
        let generator2 = SeededRandomNumberGenerator(seed: seed)

        let value1a = generator1.next()
        let value1b = generator1.next()

        let value2a = generator2.next()
        let value2b = generator2.next()

        #expect(value1a == value2a)
        #expect(value1b == value2b)
        #expect(value1a != value1b)

        let range = 1 ... 10
        let randomInt1 = generator1.randomInt(range)
        let randomInt2 = generator1.randomInt(range)

        #expect(range.contains(randomInt1))
        #expect(range.contains(randomInt2))

        let generator3 = SeededRandomNumberGenerator(seed: 999)
        let value3 = generator3.next()
        #expect(value3 != value1a)
    }
}
