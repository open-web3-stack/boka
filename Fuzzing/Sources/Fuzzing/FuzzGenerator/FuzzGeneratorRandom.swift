import Blockchain
import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "FuzzGeneratorRandom")

public class SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public func next() -> UInt64 {
        // Linear Congruential Generator formula: next = (a * current + c) mod m
        // Uses the same parameters as the classic Borland C/C++ rand() function
        state = state &* 1_103_515_245 &+ 12345
        return state
    }

    public func randomInt(_ range: ClosedRange<Int>) -> Int {
        let randomValue = next()
        let fraction = Double(randomValue % UInt64(Int32.max)) / Double(Int32.max)
        return range.lowerBound + Int(fraction * Double(range.count))
    }
}

/// Random fuzzing generator that creates pseudo-random state and blocks
public class FuzzGeneratorRandom: FuzzGenerator {
    private let seed: UInt64
    private var generator: SeededRandomNumberGenerator
    private let config: ProtocolConfigRef

    private var blockAuthor: BlockAuthor?
    private var scheduler: MockScheduler?
    private var keystore: KeyStore?
    private var dataProvider: BlockchainDataProvider?

    public init(seed: UInt64, config: ProtocolConfigRef) {
        self.seed = seed
        self.config = config
        generator = SeededRandomNumberGenerator(seed: seed)
        blockAuthor = nil
        scheduler = nil
        keystore = nil
        dataProvider = nil
    }

    // TODO: Implement pre-state generation logic
    public func generatePreState(
        timeslot _: TimeslotIndex,
        config _: ProtocolConfigRef
    ) async throws -> (stateRoot: Data32, keyValues: [FuzzKeyValue]) {
        fatalError("not implemented")
    }

    // TODO: Implement post-state generation logic
    public func generatePostState(
        timeslot _: TimeslotIndex,
        config _: ProtocolConfigRef
    ) async throws -> (stateRoot: Data32, keyValues: [FuzzKeyValue]) {
        fatalError("not implemented")
    }

    // TODO: Implement block generation logic
    public func generateBlock(timeslot _: UInt32, currentStateRef _: StateRef, config _: ProtocolConfigRef) async throws -> BlockRef {
        fatalError("not implemented")
    }
}
