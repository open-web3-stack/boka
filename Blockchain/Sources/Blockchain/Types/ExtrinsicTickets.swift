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
    public func getTickets(verifier: Bandersnatch.Verifier, entropy: Data32) throws -> [Ticket] {
        try tickets.array.map {
            let vrfInputData = SigningContext.safroleTicketInputData(entropy: entropy, attempt: $0.attempt)
            let ticketId = try verifier.ringVRFVerify(vrfInputData: vrfInputData, signature: $0.signature)
            return Ticket(id: ticketId, attempt: $0.attempt)
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

extension ExtrinsicTickets: Validate {}
