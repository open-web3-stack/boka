@testable import Blockchain
import Codec
import Foundation
import Testing
import Utils

struct BlockHeaderRefTests {
    @Test
    func headerAccessorsExposeUnsignedFields() {
        let header = makeHeader()

        #expect(header.parentHash == data32(1))
        #expect(header.priorStateRoot == data32(2))
        #expect(header.extrinsicsHash == data32(3))
        #expect(header.timeslot == 99)
        #expect(header.epoch == nil)
        #expect(header.winningTickets == nil)
        #expect(header.offendersMarkers == [data32(4), data32(5)])
        #expect(header.authorIndex == 2)
        #expect(header.vrfSignature == Data96(repeating: 6))
    }

    @Test
    func headerValidationChecksAuthorIndexAgainstValidatorCount() throws {
        let config = ProtocolConfigRef.tiny
        try makeHeader(authorIndex: 5).validateSelf(config: config)

        var invalid = makeHeader(authorIndex: ValidatorIndex(config.value.totalNumberOfValidators))
        do {
            try invalid.validateSelf(config: config)
            Issue.record("Expected invalid author index")
        } catch Header.Error.invalidAuthorIndex {
        }

        invalid.unsigned.authorIndex = 0
        try invalid.validateSelf(config: config)
    }

    @Test
    func headerRefCodecsRoundTripWrappedHeader() throws {
        let config = ProtocolConfigRef.tiny
        let header = makeHeader()
        let ref = header.asRef()

        #expect(ref.hash == header.hash())
        #expect(ref.description == "Header(hash: \(ref.hash), timeslot: \(header.timeslot))")
        #expect(Set([header]).contains(header))

        let jamDecoded = try JamDecoder.decode(HeaderRef.self, from: JamEncoder.encode(ref), withConfig: config)
        #expect(jamDecoded.value == header)
        #expect(jamDecoded.hash == header.hash())

        let jsonEncoded = try jsonEncoder(config: config).encode(ref)
        let jsonDecoded = try jsonDecoder(config: config).decode(HeaderRef.self, from: jsonEncoded)
        #expect(jsonDecoded.value == header)
        #expect(jsonDecoded.hash == header.hash())
    }

    @Test
    func blockRefExposesWrappedFieldsHashAndDescription() {
        let block = makeBlock()
        let ref = block.asRef()

        #expect(ref.header == block.header)
        #expect(ref.extrinsic == block.extrinsic)
        #expect(ref.hash == block.hash())
        #expect(block.hash() == block.header.hash())
        #expect(ref.description == "Block(hash: \(ref.hash), timeslot: \(block.header.timeslot))")
    }

    @Test
    func blockRefDummyBuildsChildFromParentRef() {
        let config = ProtocolConfigRef.tiny
        let parent = makeBlock().asRef()

        let child = BlockRef.dummy(config: config, parent: parent)

        #expect(child.header.parentHash == parent.hash)
        #expect(child.header.timeslot == parent.header.timeslot + 1)
    }

    @Test
    func blockRefCodecsRoundTripWrappedBlock() throws {
        let config = ProtocolConfigRef.tiny
        let block = makeBlock(config: config)
        let ref = block.asRef()

        let jamDecoded = try JamDecoder.decode(BlockRef.self, from: JamEncoder.encode(ref), withConfig: config)
        #expect(jamDecoded.value == block)
        #expect(jamDecoded.hash == block.hash())

        let jsonEncoded = try jsonEncoder(config: config).encode(ref)
        let jsonDecoded = try jsonDecoder(config: config).decode(BlockRef.self, from: jsonEncoded)
        #expect(jsonDecoded.value == block)
        #expect(jsonDecoded.hash == block.hash())
    }

    private func makeBlock(config: ProtocolConfigRef = .tiny) -> Block {
        Block(
            header: makeHeader(),
            extrinsic: Extrinsic.dummy(config: config),
        )
    }

    private func makeHeader(authorIndex: ValidatorIndex = 2) -> Header {
        Header(
            unsigned: Header.Unsigned(
                parentHash: data32(1),
                priorStateRoot: data32(2),
                extrinsicsHash: data32(3),
                timeslot: 99,
                epoch: nil,
                winningTickets: nil,
                authorIndex: authorIndex,
                vrfSignature: Data96(repeating: 6),
                offendersMarkers: [data32(4), data32(5)],
            ),
            seal: Data96(repeating: 7),
        )
    }

    private func jsonEncoder(config: ProtocolConfigRef) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.userInfo[.config] = config
        return encoder
    }

    private func jsonDecoder(config: ProtocolConfigRef) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[.config] = config
        return decoder
    }
}
