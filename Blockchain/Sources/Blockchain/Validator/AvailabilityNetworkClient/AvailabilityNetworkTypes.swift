import Foundation
import Utils

// MARK: - Fetch Strategy

/// Strategy for fetching shards
public enum FetchStrategy: Sendable {
    /// Fast mode: Use CE 139 (no justification)
    case fast

    /// Verified mode: Use CE 140 (with justification)
    case verified

    /// Adaptive: Start with CE 139, fallback to CE 140
    case adaptive

    /// Local-only: Don't use network, only local shards
    case localOnly
}

// MARK: - Network Metrics

/// Network operation metrics
public struct NetworkMetrics: Sendable {
    /// Total number of requests made
    public var totalRequests: Int = 0

    /// Number of successful requests
    public var successfulRequests: Int = 0

    /// Number of failed requests
    public var failedRequests: Int = 0

    /// Total number of retries
    public var totalRetries: Int = 0

    /// Total latency across all requests (seconds)
    public var totalLatency: TimeInterval = 0

    /// Minimum request latency (seconds)
    public var minLatency: TimeInterval = .infinity

    /// Maximum request latency (seconds)
    public var maxLatency: TimeInterval = 0

    /// Recent request latencies (last 100)
    public var recentLatencies: [TimeInterval] = []

    // MARK: - Fallback Usage Tracking

    /// Number of requests served from local storage
    public var localHits: Int = 0

    /// Number of CE 138 requests (Audit Shard Request)
    public var ce138Requests: Int = 0

    /// Number of CE 139 requests (Segment Shard Request - fast)
    public var ce139Requests: Int = 0

    /// Number of CE 140 requests (Segment Shard Request - verified)
    public var ce140Requests: Int = 0

    /// Number of CE 147 requests (Bundle Request)
    public var ce147Requests: Int = 0

    /// Number of CE 148 requests (Segment Request)
    public var ce148Requests: Int = 0

    /// Number of fallback operations (local → network)
    public var fallbackCount: Int = 0

    /// Average request latency
    public var averageLatency: TimeInterval {
        guard successfulRequests > 0 else { return 0 }
        return totalLatency / Double(successfulRequests)
    }

    /// Request success rate (0.0 to 1.0)
    public var successRate: Double {
        guard totalRequests > 0 else { return 1.0 }
        return Double(successfulRequests) / Double(totalRequests)
    }

    /// Median latency from recent samples
    public var medianLatency: TimeInterval {
        guard !recentLatencies.isEmpty else { return 0 }
        let sorted = recentLatencies.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        } else {
            return sorted[count / 2]
        }
    }

    /// P95 latency from recent samples
    public var p95Latency: TimeInterval {
        guard !recentLatencies.isEmpty else { return 0 }
        let sorted = recentLatencies.sorted()
        let index = Int(Double(sorted.count) * 0.95)
        return sorted[min(index, sorted.count - 1)]
    }

    /// P99 latency from recent samples
    public var p99Latency: TimeInterval {
        guard !recentLatencies.isEmpty else { return 0 }
        let sorted = recentLatencies.sorted()
        let index = Int(Double(sorted.count) * 0.99)
        return sorted[min(index, sorted.count - 1)]
    }

    public init() {}

    // MARK: - Fallback Tracking Methods

    /// Record when data is found locally (no network request)
    public mutating func recordLocalHit() {
        localHits += 1
    }

    /// Record a CE 138 request (Audit Shard Request)
    public mutating func recordCE138Request() {
        ce138Requests += 1
        fallbackCount += 1
    }

    /// Record a CE 139 request (Segment Shard Request - fast)
    public mutating func recordCE139Request() {
        ce139Requests += 1
        fallbackCount += 1
    }

    /// Record a CE 140 request (Segment Shard Request - verified)
    public mutating func recordCE140Request() {
        ce140Requests += 1
        fallbackCount += 1
    }

    /// Record a CE 147 request (Bundle Request)
    public mutating func recordCE147Request() {
        ce147Requests += 1
        fallbackCount += 1
    }

    /// Record a CE 148 request (Segment Request)
    public mutating func recordCE148Request() {
        ce148Requests += 1
        fallbackCount += 1
    }
}

// MARK: - Fallback Timeout Configuration

/// Timeout configuration for each stage of the fallback chain
public struct FallbackTimeoutConfig: Sendable {
    /// Timeout for local operations (default: 0.1s)
    public var localTimeout: TimeInterval

    /// Timeout for CE 147 (Bundle Request from guarantors) (default: 5s)
    public var ce147Timeout: TimeInterval

    /// Timeout for CE 138 (Audit Shard Request) (default: 5s)
    public var ce138Timeout: TimeInterval

    /// Timeout for CE 139 (Segment Shard Request - fast) (default: 3s)
    public var ce139Timeout: TimeInterval

    /// Timeout for CE 140 (Segment Shard Request - verified) (default: 10s)
    public var ce140Timeout: TimeInterval

    /// Timeout for CE 148 (Segment Request from guarantors) (default: 5s)
    public var ce148Timeout: TimeInterval

    public init(
        localTimeout: TimeInterval = 0.1,
        ce147Timeout: TimeInterval = 5.0,
        ce138Timeout: TimeInterval = 5.0,
        ce139Timeout: TimeInterval = 3.0,
        ce140Timeout: TimeInterval = 10.0,
        ce148Timeout: TimeInterval = 5.0,
    ) {
        self.localTimeout = localTimeout
        self.ce147Timeout = ce147Timeout
        self.ce138Timeout = ce138Timeout
        self.ce139Timeout = ce139Timeout
        self.ce140Timeout = ce140Timeout
        self.ce148Timeout = ce148Timeout
    }
}

// MARK: - Placeholder PeerManager

/// Placeholder for PeerManager integration
///
/// In production, this would be the actual PeerManager from the Node module.
public struct PeerManager {
    // Placeholder - would contain connection management logic
}
