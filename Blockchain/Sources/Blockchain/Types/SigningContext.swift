import Foundation
import Utils

public enum SigningContext {
    /// XA = $jam_available: Ed25519 Availability assurances.
    public static let available = Data("jam_available".utf8)

    /// XB = $jam_beefy: bls Accumulate-result-root-mmr commitment.
    public static let beefy = Data("jam_beefy".utf8)

    /// XE = $jam_entropy: On-chain entropy generation.
    public static let entropy = Data("jam_entropy".utf8)

    /// XF = $jam_fallback_seal: Bandersnatch Fallback block seal.
    public static let fallbackSeal = Data("jam_fallback_seal".utf8)

    /// XG = $jam_guarantee: Ed25519 Guarantee statements.
    public static let guarantee = Data("jam_guarantee".utf8)

    /// XI = $jam_announce: Ed25519 Audit announcement statements.
    public static let announce = Data("jam_announce".utf8)

    /// XT = $jam_ticket_seal: Bandersnatch Ringvrf Ticket generation and regular block seal.
    public static let ticketSeal = Data("jam_ticket_seal".utf8)

    /// XU = $jam_audit: Bandersnatch Audit selection entropy.
    public static let audit = Data("jam_audit".utf8)

    /// X_top = $jam_valid: Ed25519 Judgements for valid work-reports.
    public static let valid = Data("jam_valid".utf8)

    /// X_bot = $jam_invalid: Ed25519 Judgements for invalid work-reports.
    public static let invalid = Data("jam_invalid".utf8)
}

extension SigningContext {
    public static func safroleTicketInputData(entropy: Data32, attempt: TicketIndex) -> Data {
        var vrfInputData = SigningContext.ticketSeal
        vrfInputData.append(entropy.data)
        vrfInputData.append(attempt)
        return vrfInputData
    }

    public static func ticketSealInputData(entropy: Data32, attempt: TicketIndex) -> Data {
        var vrfInputData = SigningContext.ticketSeal
        vrfInputData.append(entropy.data)
        vrfInputData.append(attempt)
        return vrfInputData
    }

    public static func fallbackSealInputData(entropy: Data32) -> Data {
        var vrfInputData = SigningContext.fallbackSeal
        vrfInputData.append(entropy.data)
        return vrfInputData
    }

    public static func entropyInputData(entropy: Data32) -> Data {
        var vrfInputData = SigningContext.entropy
        vrfInputData.append(entropy.data)
        return vrfInputData
    }
}
