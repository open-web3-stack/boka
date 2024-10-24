import Blockchain
import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "NetworkManager")

enum SendTarget {
    case safroleStep1Validator
    case currentValidators
}

public final class NetworkManager: Sendable {
    private let network: Network
    private let blockchain: Blockchain
    private let subscriptions: EventSubscriptions
    // This is for development only
    // Those peers will receive all the messages regardless the target
    private let devPeers: Set<NetAddr>

    public init(config: Network.Config, blockchain: Blockchain, eventBus: EventBus, devPeers: Set<NetAddr>) async throws {
        let handler = HandlerImpl(blockchain: blockchain)
        network = try await Network(
            config: config,
            protocolConfig: blockchain.config,
            genesisHeader: blockchain.dataProvider.genesisBlockHash,
            handler: handler
        )
        self.blockchain = blockchain
        subscriptions = EventSubscriptions(eventBus: eventBus)
        self.devPeers = devPeers

        for peer in devPeers {
            _ = try network.connect(to: peer, mode: .validator)
        }

        logger.info("P2P Listening on \(try! network.listenAddress())")

        Task {
            await subscriptions.subscribe(
                RuntimeEvents.SafroleTicketsGenerated.self,
                id: "NetworkManager.SafroleTicketsGenerated"
            ) { [weak self] event in
                await self?.on(safroleTicketsGenerated: event)
            }
        }
    }

    private func getSendTarget(target: SendTarget) -> Set<NetAddr> {
        // TODO: get target from onchain state
        switch target {
        case .safroleStep1Validator:
            // TODO: only send to the selected validator in the spec
            devPeers
        case .currentValidators:
            // TODO: read onchain state for validators
            devPeers
        }
    }

    private func send<R: Decodable>(
        message: CERequest,
        target: SendTarget,
        responseType: R.Type,
        responseHandler: @Sendable @escaping (Result<R, Error>) async -> Void
    ) async {
        let targets = getSendTarget(target: target)
        for target in targets {
            Task {
                let res = await Result {
                    try await network.send(to: target, message: message)
                }
                .flatMap { data in
                    Result(catching: {
                        try JamDecoder.decode(responseType, from: data, withConfig: blockchain.config)
                    })
                }
                await responseHandler(res)
            }
        }
    }

    private func send(message: CERequest, target: SendTarget) async {
        let targets = getSendTarget(target: target)
        for target in targets {
            Task {
                // not expecting a response
                // TODO: handle errors and ensure no data is returned
                _ = try await network.send(to: target, message: message)
            }
        }
    }

    private func on(safroleTicketsGenerated event: RuntimeEvents.SafroleTicketsGenerated) async {
        for ticket in event.items {
            await send(
                message: .safroleTicket1(.init(
                    epochIndex: event.epochIndex,
                    attempt: ticket.ticket.attempt,
                    proof: ticket.ticket.signature
                )),
                target: .safroleStep1Validator
            )
        }
    }

    public func getPeersCount() -> Int {
        network.getPeersCount()
    }
}

struct HandlerImpl: NetworkProtocolHandler {
    let blockchain: Blockchain

    func handle(ceRequest: CERequest) async throws -> (any Encodable)? {
        switch ceRequest {
        case let .safroleTicket1(message):
            blockchain.publish(event: RuntimeEvents.SafroleTicketsReceived(
                items: [
                    ExtrinsicTickets.TicketItem(
                        attempt: message.attempt,
                        signature: message.proof
                    ),
                ]
            ))
            // TODO: rebroadcast to other peers after some time
            return nil
        case let .safroleTicket2(message):
            blockchain.publish(event: RuntimeEvents.SafroleTicketsReceived(
                items: [
                    ExtrinsicTickets.TicketItem(
                        attempt: message.attempt,
                        signature: message.proof
                    ),
                ]
            ))
            return nil
        }
    }

    func handle(upMessage: UPMessage) async throws {
        switch upMessage {
        case let .blockAnnouncement(message):
            logger.debug("received block announcement: \(message)")
            // TODO: handle it
        }
    }
}
