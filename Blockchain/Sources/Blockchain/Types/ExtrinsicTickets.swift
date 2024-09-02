import Foundation
import Utils

public struct ExtrinsicTickets: Sendable, Equatable, Codable {
    public struct TicketItem: Sendable, Equatable, Codable {
        public var attempt: TicketIndex
        public var signature: BandersnatchRingVRFProof

        public init(
            attempt: TicketIndex,
            signature: BandersnatchRingVRFProof
        ) {
            self.attempt = attempt
            self.signature = signature
        }
    }

    public var tickets: ConfigLimitedSizeArray<
        TicketItem,
        ProtocolConfig.Int0,
        ProtocolConfig.MaxTicketsPerExtrinsic
    >

    public init(
        tickets: ConfigLimitedSizeArray<
            TicketItem,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxTicketsPerExtrinsic
        >
    ) {
        self.tickets = tickets
    }
}

extension ExtrinsicTickets: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> ExtrinsicTickets {
        ExtrinsicTickets(tickets: try! ConfigLimitedSizeArray(config: config))
    }
}

extension ExtrinsicTickets {
    public func getTickets(verifier: Verifier, entropy: Data32) throws -> [Ticket] {
        try tickets.array.map {
            var vrfInputData = SigningContext.ticketSeal
            vrfInputData.append(entropy.data)
            vrfInputData.append($0.attempt)
            let ticketId = verifier.ringVRFVerify(vrfInputData: vrfInputData, auxData: Data(), signature: $0.signature.data)
            return try Ticket(id: ticketId.get(), attempt: $0.attempt)
        }
    }
}

extension ExtrinsicTickets.TicketItem: Validate {
    public enum Error: Swift.Error {
        case invalidAttempt
    }

    public typealias Config = ProtocolConfigRef
    public func validate(config: Config) throws {
        guard attempt < UInt32(config.value.ticketEntriesPerValidator) else {
            throw Error.invalidAttempt
        }
    }
}

extension ExtrinsicTickets: Validate {
    public func validate(config: Config) throws {
        try tickets.validate(config: config)
    }
}
