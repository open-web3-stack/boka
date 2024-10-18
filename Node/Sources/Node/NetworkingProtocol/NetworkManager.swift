import Blockchain
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "NetworkManager")

public final class NetworkManager: Sendable {
    private let network: Network
    // This is for development only
    // Will assume those peers are also validators
    private let devPeers: Set<NetAddr> = []

    public init(config: Network.Config, blockchain: Blockchain) throws {
        let handler = HandlerImpl(blockchain: blockchain)
        network = try Network(
            config: config,
            protocolConfig: blockchain.config,
            genesisHeader: blockchain.dataProvider.genesisBlockHash,
            handler: handler
        )
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
