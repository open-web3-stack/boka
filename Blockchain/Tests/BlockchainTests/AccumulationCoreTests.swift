@testable import Blockchain
import Codec
import Foundation
import Testing
import Utils

struct AccumulationCoreTests {
    private let config = ProtocolConfigRef.tiny

    @Test
    func accumulationInputRoundTripsOperandTupleVariant() throws {
        let operand = OperandTuple(
            packageHash: data32(1),
            segmentRoot: data32(2),
            authorizerHash: data32(3),
            payloadHash: data32(4),
            gasLimit: Gas(50),
            workResult: WorkResult(.success(Data([5, 6]))),
            authorizerTrace: Data([7, 8]),
        )

        let decoded = try JamDecoder.decode(
            AccumulationInput.self,
            from: JamEncoder.encode(AccumulationInput(operandTuple: operand)),
        )

        #expect(decoded.inputType == .operandTuple)
        #expect(decoded.deferredTransfers == nil)
        #expect(decoded.operandTuple?.packageHash == operand.packageHash)
        #expect(decoded.operandTuple?.segmentRoot == operand.segmentRoot)
        #expect(decoded.operandTuple?.authorizerHash == operand.authorizerHash)
        #expect(decoded.operandTuple?.payloadHash == operand.payloadHash)
        #expect(decoded.operandTuple?.gasLimit == operand.gasLimit)
        #expect(decoded.operandTuple?.workResult == operand.workResult)
        #expect(decoded.operandTuple?.authorizerTrace == operand.authorizerTrace)
    }

    @Test
    func accumulationInputRoundTripsDeferredTransfersVariant() throws {
        let transfers = DeferredTransfers(
            sender: 1,
            destination: 2,
            amount: Balance(300),
            memo: data128(4),
            gasLimit: Gas(500),
        )

        let decoded = try JamDecoder.decode(
            AccumulationInput.self,
            from: JamEncoder.encode(AccumulationInput(deferredTransfers: transfers)),
        )

        #expect(decoded.inputType == .deferredTransfers)
        #expect(decoded.operandTuple == nil)
        #expect(decoded.deferredTransfers?.sender == transfers.sender)
        #expect(decoded.deferredTransfers?.destination == transfers.destination)
        #expect(decoded.deferredTransfers?.amount == transfers.amount)
        #expect(decoded.deferredTransfers?.memo == transfers.memo)
        #expect(decoded.deferredTransfers?.gasLimit == transfers.gasLimit)
    }

    @Test
    func accumulationInputRejectsUnknownVariant() throws {
        #expect(throws: DecodingError.self) {
            _ = try JamDecoder.decode(AccumulationInput.self, from: JamEncoder.encode(UInt(2)))
        }
    }

    @Test
    func accountChangesRejectDuplicateNewAccounts() {
        var first = AccountChanges()
        first.addNewAccount(index: 10, account: ServiceAccount.dummy(config: config))

        var second = AccountChanges()
        second.addNewAccount(index: 10, account: ServiceAccount.dummy(config: config))

        expectAccumulationError(.duplicatedNewService) {
            try first.checkAndMerge(with: second)
        }
    }

    @Test
    func accountChangesRejectDuplicateAlteredAccounts() {
        var first = AccountChanges()
        first.addStorageUpdate(index: 11, key: Data([1]), value: Data([2]))

        var second = AccountChanges()
        second.addPreimageUpdate(index: 11, hash: data32(3), value: Data([4]))

        expectAccumulationError(.duplicatedContributionToService) {
            try first.checkAndMerge(with: second)
        }
    }

    @Test
    func accountChangesRejectDuplicateRemovedAccounts() {
        var first = AccountChanges()
        first.addRemovedAccount(index: 12)

        var second = AccountChanges()
        second.addRemovedAccount(index: 12)

        expectAccumulationError(.duplicatedRemovedService) {
            try first.checkAndMerge(with: second)
        }
    }

    @Test
    func accountChangesMergeIndependentUpdatesInOrder() throws {
        var first = AccountChanges()
        first.addNewAccount(index: 20, account: ServiceAccount.dummy(config: config))
        first.addStorageUpdate(index: 21, key: Data([1]), value: Data([2]))

        var second = AccountChanges()
        second.addRemovedAccount(index: 22)
        second.addPreimageUpdate(index: 23, hash: data32(3), value: Data([4]))

        try first.checkAndMerge(with: second)

        #expect(Set(first.newAccounts.keys) == [20])
        #expect(first.altered == [21, 23])
        #expect(first.removed == [22])
        #expect(first.updates.count == 4)
    }

    private func expectAccumulationError(
        _ expected: AccumulationError,
        operation: () throws -> Void,
    ) {
        do {
            try operation()
            Issue.record("Expected \(expected)")
        } catch let error as AccumulationError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected), got \(error)")
        }
    }
}

