import Foundation
import TracingUtils

private let logger = Logger(label: "StorageMonitoring")

/// Configuration for storage monitoring
public struct StorageMonitoringConfig: Sendable {
    /// Monitoring interval in seconds (default: 60 seconds)
    public var monitoringInterval: TimeInterval

    /// Maximum storage bytes before triggering cleanup
    public var maxStorageBytes: Int

    /// Storage pressure threshold for aggressive cleanup (0.0-1.0)
    public var aggressiveCleanupThreshold: Double

    /// Whether monitoring is enabled
    public var isEnabled: Bool

    public init(
        monitoringInterval: TimeInterval = 60.0,
        maxStorageBytes: Int = 100 * 1024 * 1024 * 1024, // 100 GB default
        aggressiveCleanupThreshold: Double = 0.85, // 85%
        isEnabled: Bool = true,
    ) {
        self.monitoringInterval = monitoringInterval
        self.maxStorageBytes = maxStorageBytes
        self.aggressiveCleanupThreshold = aggressiveCleanupThreshold
        self.isEnabled = isEnabled
    }
}

/// Service for automated storage monitoring and cleanup
public actor StorageMonitoring {
    private let storageMonitor: StorageMonitor
    private var monitoringConfig = StorageMonitoringConfig()
    private var monitoringTask: Task<Void, Never>?

    public init(storageMonitor: StorageMonitor) {
        self.storageMonitor = storageMonitor
    }

    /// Configure storage monitoring
    /// - Parameter config: Monitoring configuration
    public func configure(_ config: StorageMonitoringConfig) {
        monitoringConfig = config
        logger.info(
            """
            Storage monitoring configured: interval=\(config.monitoringInterval)s, \
            maxBytes=\(config.maxStorageBytes), \
            threshold=\(Int(config.aggressiveCleanupThreshold * 100))%
            """,
        )
    }

    /// Start storage monitoring background task
    ///
    /// Periodically checks storage usage and performs cleanup when needed.
    /// Call this method during service initialization.
    public func start() {
        guard monitoringConfig.isEnabled else {
            logger.info("Storage monitoring is disabled")
            return
        }

        // Stop existing task if running
        stop()

        // Start new monitoring task
        monitoringTask = Task {
            await runMonitoringLoop()
        }

        logger.info("Started storage monitoring (interval: \(monitoringConfig.monitoringInterval)s)")
    }

    /// Stop storage monitoring background task
    public func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        logger.info("Stopped storage monitoring")
    }

    /// Storage monitoring loop
    private func runMonitoringLoop() async {
        var consecutiveWarnings = 0
        let maxWarnings = 5 // After 5 warnings, perform aggressive cleanup

        while !Task.isCancelled {
            do {
                let usage = try await storageMonitor.getStorageUsage()
                let pressure = StoragePressure.from(usage: usage, maxBytes: monitoringConfig.maxStorageBytes)

                switch pressure {
                case .normal:
                    // Reset warning counter when pressure is normal
                    if consecutiveWarnings > 0 {
                        let maxStorageMB = monitoringConfig.maxStorageBytes / 1024 / 1024
                        logger.info(
                            "Storage pressure returned to normal: \(usage.totalMB) MB / \(maxStorageMB) MB",
                        )
                        consecutiveWarnings = 0
                    }

                case .warning:
                    consecutiveWarnings += 1
                    let maxStorageMB = monitoringConfig.maxStorageBytes / 1024 / 1024
                    let usagePercentage = Int(
                        Double(usage.totalBytes) / Double(monitoringConfig.maxStorageBytes) * 100,
                    )
                    logger.warning(
                        "Storage pressure warning: \(usage.totalMB) MB / \(maxStorageMB) MB (\(usagePercentage)% used)",
                    )

                case .critical:
                    consecutiveWarnings += 1
                    let maxStorageMB = monitoringConfig.maxStorageBytes / 1024 / 1024
                    let usagePercentage = Int(
                        Double(usage.totalBytes) / Double(monitoringConfig.maxStorageBytes) * 100,
                    )
                    logger.error(
                        "⚠️ CRITICAL storage pressure: \(usage.totalMB) MB / \(maxStorageMB) MB (\(usagePercentage)% used)",
                    )

                    // Perform aggressive cleanup if we haven't recently
                    if consecutiveWarnings >= maxWarnings {
                        logger.error("Initiating aggressive cleanup due to critical storage pressure")

                        let targetBytes = Int(
                            Double(monitoringConfig.maxStorageBytes) * (1.0 - monitoringConfig.aggressiveCleanupThreshold),
                        )
                        let reclaimed = try await storageMonitor.aggressiveCleanup(targetBytes: targetBytes)

                        logger.info("Aggressive cleanup reclaimed \(reclaimed) bytes")

                        // Reset counter after cleanup attempt
                        consecutiveWarnings = 0
                    }

                case .emergency:
                    consecutiveWarnings += 1
                    let maxStorageMB = monitoringConfig.maxStorageBytes / 1024 / 1024
                    let usagePercentage = Int(
                        Double(usage.totalBytes) / Double(monitoringConfig.maxStorageBytes) * 100,
                    )
                    logger.critical(
                        """
                        🚨 EMERGENCY storage pressure: \(usage.totalMB) MB / \(maxStorageMB) MB \
                        (\(usagePercentage)% used) - System may become unstable!
                        """,
                    )

                    // Immediate aggressive cleanup
                    let targetBytes = usage.totalBytes / 2 // Try to free 50%
                    let reclaimed = try await storageMonitor.aggressiveCleanup(targetBytes: targetBytes)

                    logger.critical("Emergency cleanup reclaimed \(reclaimed) bytes")
                }

            } catch {
                logger.error("Storage monitoring error: \(error)")
            }

            // Wait for next check (or until cancelled)
            try? await Task.sleep(nanoseconds: UInt64(monitoringConfig.monitoringInterval * 1_000_000_000))
        }

        logger.info("Storage monitoring loop ended")
    }

    /// Get current storage pressure level
    /// - Returns: Current storage pressure
    public func getCurrentStoragePressure() async throws -> StoragePressure {
        let usage = try await storageMonitor.getStorageUsage()
        return StoragePressure.from(usage: usage, maxBytes: monitoringConfig.maxStorageBytes)
    }
}
