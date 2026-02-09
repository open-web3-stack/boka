import Foundation
import Testing
@testable import Utils

@Suite struct KeccakTests {
    @Test func hash() {
        var keccak = Keccak()
        keccak.update(Data("test".utf8))
        #expect(keccak.finalize().toHexString() == "9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658")
    }

    @Test func update() {
        var keccak = Keccak()
        keccak.update(Data("test".utf8))
        keccak.update(Data("1111".utf8))
        keccak.update(Data("2222".utf8))
        #expect(keccak.finalize().toHexString() == "dc14ef6d46da835e8d0f5b154954b2255ab8cd49b8065a8ffbb47358f0d86de7")
    }
}
