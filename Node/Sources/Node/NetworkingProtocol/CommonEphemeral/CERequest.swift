import Blockchain
import Codec
import Foundation
import Networking

public enum CERequest: Sendable {
    case safroleTicket1(SafroleTicketMessage)
    case safroleTicket2(SafroleTicketMessage)
}

extension CERequest: RequestProtocol {
    public typealias StreamKind = CommonEphemeralStreamKind

    public func encode() throws -> Data {
        switch self {
        case let .safroleTicket1(message):
            try JamEncoder.encode(message)
        case let .safroleTicket2(message):
            try JamEncoder.encode(message)
        }
    }

    public var kind: CommonEphemeralStreamKind {
        switch self {
        case .safroleTicket1:
            .safroleTicket1
        case .safroleTicket2:
            .safroleTicket2
        }
    }

    static func getType(kind: CommonEphemeralStreamKind) -> Decodable.Type {
        switch kind {
        case .safroleTicket1:
            SafroleTicketMessage.self
        case .safroleTicket2:
            SafroleTicketMessage.self
        default:
            fatalError("unimplemented")
        }
    }

    static func from(kind: CommonEphemeralStreamKind, data: any Decodable) -> CERequest? {
        switch kind {
        case .safroleTicket1:
            guard let message = data as? SafroleTicketMessage else {
                return nil
            }
            return .safroleTicket1(message)
        case .safroleTicket2:
            guard let message = data as? SafroleTicketMessage else {
                return nil
            }
            return .safroleTicket2(message)
        default:
            fatalError("unimplemented")
        }
    }
}

extension CERequest {
    public func handle(blockchain: Blockchain) async throws -> (any Encodable)? {
        switch self {
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
}
