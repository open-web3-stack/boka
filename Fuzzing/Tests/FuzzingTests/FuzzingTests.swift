import Blockchain
import Foundation
@testable import Fuzzing
import Testing

struct FuzzingTests {
    @Test func seededRandomNumberGenerator() {
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

    @Test func targetSessionRejectsSecondInitializeAndFreshSessionStartsCleanly() throws {
        var session = FuzzingTarget.Session()

        guard case .handshake = try session.receive(.peerInfo(.init(name: "session-test-fuzzer", fuzzFeatures: 0))) else {
            Issue.record("Expected handshake action")
            return
        }

        let initialize = FuzzingMessage.initialize(FuzzInitialize(
            header: Header.dummy(config: ProtocolConfigRef.tiny),
            state: [],
            ancestry: [],
        ))
        guard case .initialize = try session.receive(initialize) else {
            Issue.record("Expected initialize action")
            return
        }

        do {
            _ = try session.receive(initialize)
            Issue.record("Expected second Initialize to fail")
        } catch FuzzingTarget.FuzzingTargetError.protocolViolation {
            // Expected.
        } catch {
            Issue.record("Expected protocol violation, got \(error)")
        }

        var freshSession = FuzzingTarget.Session()
        guard case .handshake = try freshSession.receive(.peerInfo(.init(name: "session-test-fuzzer", fuzzFeatures: 0))) else {
            Issue.record("Expected fresh handshake action")
            return
        }
        guard case .initialize = try freshSession.receive(initialize) else {
            Issue.record("Expected fresh initialize action")
            return
        }
    }
}
