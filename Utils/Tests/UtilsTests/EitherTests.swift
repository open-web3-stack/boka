import Codec
import Foundation
import Testing

@testable import Utils

struct EitherTests {
    @Test(arguments: [
        Either<String, Int>.left("Hello"),
        Either<String, Int>.right(42),
    ])
    func testAccessors(either: Either<String, Int>) {
        if let left = either.left {
            #expect(left == "Hello")
            #expect(either.right == nil)
        } else if let right = either.right {
            #expect(right == 42)
            #expect(either.left == nil)
        }
    }

    @Test(arguments: [
        (Either<String, Int>.left("Test"), Either<String, Int>.left("Test"), true),
        (Either<String, Int>.right(100), Either<String, Int>.right(100), true),
        (Either<String, Int>.left("A"), Either<String, Int>.right(100), false),
        (Either<String, Int>.right(42), Either<String, Int>.right(100), false)
    ])
    func equality(lhs: Either<String, Int>, rhs: Either<String, Int>, expected: Bool) {
        #expect((lhs == rhs) == expected)
    }

    @Test(arguments: [
        Either<String, Int>.left("Left Value"),
        Either<String, Int>.right(123)
    ])
    func JSONCoding(either: Either<String, Int>) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(either)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Either<String, Int>.self, from: data)
        #expect(decoded == either)
    }

    @Test(arguments: [
        Either<String, Int>.left("Jam Codec Left"),
        Either<String, Int>.right(456),
    ])
    func JamCoding(either: Either<String, Int>) throws {
        let encoded = try JamEncoder.encode(either)
        let decoder = JamDecoder(data: encoded)
        let decoded = try decoder.decode(Either<String, Int>.self)
        #expect(decoded == either)
    }

    @Test(arguments: [
        (Either<String, Int>.left("Describe Me"), "Left(Describe Me)"),
        (Either<String, Int>.right(789), "Right(789)"),
    ])
    func description(either: Either<String, Int>, expected: String) {
        #expect(either.description == expected)
    }

    @Test(arguments: [
        Either<String, Int>.left("Size Test"),
        Either<String, Int>.right(999)
    ])
    func testEncodedSize(either: Either<String, Int>) {
        let encodedSize = either.left.encodedSize
        print("encodedSize: \(encodedSize)")
        #expect(encodedSize > 0)
    }

    @Test(arguments: [
        Either<Int, String>.left(42),
        Either<Int, String>.right("hello"),
    ])
    func maybeEitherInit(either: Either<Int, String>) {
        let maybe = MaybeEither(either)
        #expect(maybe.value == either)
    }

    @Test(arguments: [
        42,
        -1,
        1000,
    ])
    func maybeEitherInitLeft(left: Int) {
        let maybe = MaybeEither<Int, String>(left: left)
        #expect(maybe.value == .left(left))
    }

    @Test(arguments: [
        "hello",
        "world",
        "",
    ])
    func maybeEitherInitRight(right: String) {
        let maybe = MaybeEither<Int, String>(right: right)
        #expect(maybe.value == .right(right))
    }

    @Test(arguments: [
        Either<Int, Int>.left(42),
        Either<Int, Int>.right(99),
    ])
    func testMaybeEitherUnwrapped(either: Either<Int, Int>) {
        let maybe = MaybeEither(either)
        #expect(maybe.unwrapped == (either == .left(42) ? 42 : 99))
    }
}
