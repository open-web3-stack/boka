import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "SafroleService")

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
        let tickets = try await generateTickets(state: state)
        if let tickets {
            await publish(tickets)
        }
    }

    private func generateTickets(state: StateRef) async throws -> RuntimeEvents.NewSafroleTickets? {
        var items = [ExtrinsicTickets.TicketItem]()

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

                var vrfInputData = SigningContext.safroleTicketInputData(entropy: state.value.entropyPool.t2, attempt: 0)

                let sig1 = try prover.ringVRFSign(vrfInputData: vrfInputData)

                vrfInputData[vrfInputData.count - 1] = TicketIndex(1)

                let sig2 = try prover.ringVRFSign(vrfInputData: vrfInputData)

                items.append(.init(
                    attempt: 0,
                    signature: sig1
                ))

                items.append(.init(
                    attempt: 1,
                    signature: sig2
                ))
            }
        }

        if items.isEmpty {
            logger.debug("Not in next validators")
            return nil
        }

        return .init(items: items)
    }
}
