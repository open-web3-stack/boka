import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "SafroleService")

public struct NewSafroleTickets: Event {
    public let items: [ExtrinsicTickets.TicketItem]
}

public final class SafroleService: @unchecked Sendable {
    private let config: ProtocolConfigRef
    private let eventBus: EventBus
    private let keystore: KeyStore
    private var subscriptionToken: EventBus.SubscriptionToken?

    private let ringContext: Bandersnatch.RingContext

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        keystore: KeyStore
    ) async {
        self.config = config
        self.eventBus = eventBus
        self.keystore = keystore

        ringContext = try! Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))

        subscriptionToken = await eventBus.subscribe(BlockImported.self) { [weak self] event in
            try await self?.on(blockImported: event)
        }
    }

    deinit {
        let eventBus = self.eventBus
        if let subscriptionToken = self.subscriptionToken {
            Task {
                await eventBus.unsubscribe(token: subscriptionToken)
            }
        }
    }

    public func on(genesis: StateRef) async {
        await withSpan("on(genesis)", logger: logger) { _ in
            try await generateAndSubmitTickets(state: genesis)
        }
    }

    private func on(blockImported event: BlockImported) async throws {
        if event.isNewEpoch(config: config) {
            try await generateAndSubmitTickets(state: event.state)
        }
    }

    private func generateAndSubmitTickets(state: StateRef) async throws {
        let tickets = try await generateTickets(state: state)
        if let tickets {
            await eventBus.publish(tickets)
        }
    }

    private func generateTickets(state: StateRef) async throws -> NewSafroleTickets? {
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

                var vrfInputData = SigningContext.ticketSeal
                vrfInputData.append(state.value.entropyPool.t2.data)
                vrfInputData.append(TicketIndex(0))

                let sig1 = try prover.ringVRFSign(vrfInputData: vrfInputData, auxData: Data())

                vrfInputData[vrfInputData.count - 1] = TicketIndex(1)

                let sig2 = try prover.ringVRFSign(vrfInputData: vrfInputData, auxData: Data())

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

        return NewSafroleTickets(items: items)
    }
}
