import Foundation

/// Constants used throughout the data availability system
public enum DataAvailabilityConstants {
    // MARK: - Reed-Solomon Parameters

    /// Minimum number of validators needed to reconstruct data (342 of 1023)
    /// This is the threshold for Reed-Solomon erasure coding
    public static let minimumValidatorResponses = 342

    /// Total number of shards in Reed-Solomon encoding
    public static let totalShards = 1023

    // MARK: - Retention Periods

    /// Number of epochs to retain audit data
    /// After this period, old audit data is automatically cleaned up
    public static let auditRetentionEpochs: EpochIndex = 6

    /// Number of epochs to retain D3L (Data Distribution & Discovery Layer) data
    /// Longer retention period for D3L data compared to audit data
    public static let d3lRetentionEpochs: EpochIndex = 672

    // MARK: - Timeouts

    /// Default timeout for network requests (in seconds)
    public static let requestTimeout: TimeInterval = 5.0

    // MARK: - Protocol Message Size Limits

    /// Maximum number of segments to request in a single batch (CE 148: W_M)
    public static let maxSegmentsPerRequest = 3072

    /// Maximum number of segment shards to request in a single batch (CE 139/140)
    public static let maxSegmentShardsPerRequest = 6144
}
