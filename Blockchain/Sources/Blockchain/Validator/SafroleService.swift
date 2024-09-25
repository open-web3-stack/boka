import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "SafroleService")

public struct TicketItemAndOutput: Comparable, Sendable, Codable {
    public let ticket: ExtrinsicTickets.TicketItem
    public let output: Data32

    public static func < (lhs: TicketItemAndOutput, rhs: TicketItemAndOutput) -> Bool {
        lhs.output < rhs.output
    }

    public static func == (lhs: TicketItemAndOutput, rhs: TicketItemAndOutput) -> Bool {
        lhs.output == rhs.output && lhs.ticket == rhs.ticket
    }
}

public final class SafroleService: ServiceBase, @unchecked Sendable {
    private let keystore: KeyStore
    private let ringContext: Bandersnatch.RingContext

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        keystore: KeyStore
    ) async {
        self.keystore = keystore
        ringContext = try! Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))

        super.init(config, eventBus)

        await subscribe(RuntimeEvents.BlockImported.self) { [weak self] event in
            try await self?.on(blockImported: event)
        }
    }

    public func on(genesis: StateRef) async {
        await withSpan("on(genesis)", logger: logger) { _ in
            try await generateAndSubmitTickets(state: genesis)
        }
    }

    private func on(blockImported event: RuntimeEvents.BlockImported) async throws {
        if event.isNewEpoch(config: config) {
            try await generateAndSubmitTickets(state: event.state)
        }
    }

    private func generateAndSubmitTickets(state: StateRef) async throws {
        let events = try await generateTickets(state: state)
        for event in events {
            await publish(event)
        }
    }

    private func generateTickets(state: StateRef) async throws -> [RuntimeEvents.SafroleTicketsGenerated] {
        var events = [RuntimeEvents.SafroleTicketsGenerated]()

        for (idx, validator) in state.value.nextValidators.enumerated() {
            guard let pubkey = try? Bandersnatch.PublicKey(data: validator.bandersnatch) else {
                continue
            }

            guard let secret = await keystore.get(Bandersnatch.self, publicKey: pubkey) else {
                continue
            }

            logger.debug("Generating tickets for validator \(pubkey)")

            try withSpan("generateTickets") { _ in
                let pubkeys = try state.value.nextValidators.map {
                    try Bandersnatch.PublicKey(data: $0.bandersnatch)
                }

                let prover = Bandersnatch.Prover(sercret: secret, ring: pubkeys, proverIdx: UInt(idx), ctx: ringContext)
                let verifier = try Bandersnatch.Verifier(
                    ctx: ringContext,
                    commitment: Bandersnatch.RingCommitment(data: state.value.safroleState.ticketsVerifier)
                )

                var vrfInputData = SigningContext.safroleTicketInputData(entropy: state.value.entropyPool.t2, attempt: 0)

                let sig1 = try prover.ringVRFSign(vrfInputData: vrfInputData)
                let out1 = try verifier.ringVRFVerify(vrfInputData: vrfInputData, signature: sig1)

                vrfInputData[vrfInputData.count - 1] = TicketIndex(1)

                let sig2 = try prover.ringVRFSign(vrfInputData: vrfInputData)
                let out2 = try verifier.ringVRFVerify(vrfInputData: vrfInputData, signature: sig2)

                events.append(.init(
                    items: [
                        .init(ticket: .init(attempt: 0, signature: sig1), output: out1),
                        .init(ticket: .init(attempt: 1, signature: sig2), output: out2),
                    ],
                    publicKey: secret.publicKey
                ))
            }
        }

        if events.isEmpty {
            logger.debug("Not in next validators")
        }

        return events
    }
}
