import Foundation

public enum SigningContext {
    /// XA = $jam_available: Ed25519 Availability assurances.
    static var available: Data {
        Data("jam_available".utf8)
    }

    /// XB = $jam_beefy: bls Accumulate-result-root-mmr commitment.
    static var beefy: Data {
        Data("jam_beefy".utf8)
    }

    /// XE = $jam_entropy: On-chain entropy generation.
    static var entropy: Data {
        Data("jam_entropy".utf8)
    }

    /// XF = $jam_fallback_seal: Bandersnatch Fallback block seal.
    static var fallbackSeal: Data {
        Data("jam_fallback_seal".utf8)
    }

    /// XG = $jam_guarantee: Ed25519 Guarantee statements.
    static var guarantee: Data {
        Data("jam_guarantee".utf8)
    }

    /// XI = $jam_announce: Ed25519 Audit announcement statements.
    static var announce: Data {
        Data("jam_announce".utf8)
    }

    /// XT = $jam_ticket_seal: Bandersnatch Ringvrf Ticket generation and regular block seal.
    static var ticketSeal: Data {
        Data("jam_ticket_seal".utf8)
    }

    /// XU = $jam_audit: Bandersnatch Audit selection entropy.
    static var audit: Data {
        Data("jam_audit".utf8)
    }

    /// X_top = $jam_valid: Ed25519 Judgements for valid work-reports.
    static var valid: Data {
        Data("jam_valid".utf8)
    }

    /// X_bot = $jam_invalid: Ed25519 Judgements for invalid work-reports.
    static var invalid: Data {
        Data("jam_invalid".utf8)
    }
}
