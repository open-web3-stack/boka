public enum SigningContext {
    /// XA = $jam_available: Ed25519 Availability assurances.
    static var available: String {
        "jam_available"
    }

    /// XB = $jam_beefy: bls Accumulate-result-root-mmr commitment.
    static var beefy: String {
        "jam_beefy"
    }

    /// XE = $jam_entropy: On-chain entropy generation.
    static var entropy: String {
        "jam_entropy"
    }

    /// XF = $jam_fallback_seal: Bandersnatch Fallback block seal.
    static var fallbackSeal: String {
        "jam_fallback_seal"
    }

    /// XG = $jam_guarantee: Ed25519 Guarantee statements.
    static var guarantee: String {
        "jam_guarantee"
    }

    /// XI = $jam_announce: Ed25519 Audit announcement statements.
    static var announce: String {
        "jam_announce"
    }

    /// XT = $jam_ticket_seal: Bandersnatch Ringvrf Ticket generation and regular block seal.
    static var ticketSeal: String {
        "jam_ticket_seal"
    }

    /// XU = $jam_audit: Bandersnatch Audit selection entropy.
    static var audit: String {
        "jam_audit"
    }

    /// X_top = $jam_valid: Ed25519 Judgements for valid work-reports.
    static var valid: String {
        "jam_valid"
    }

    /// X_bot = $jam_invalid: Ed25519 Judgements for invalid work-reports.
    static var invalid: String {
        "jam_invalid"
    }
}
