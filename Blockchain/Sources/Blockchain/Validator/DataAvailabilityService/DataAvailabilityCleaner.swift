import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "DataAvailabilityCleaner")

/// Service for cleaning up old data availability data
///
/// Handles purging of expired audit bundles and D³L segments
/// according to GP 14.3.1 retention requirements
public actor DataAvailabilityCleaner {
    private let erasureCodingDataStore: ErasureCodingDataStore?

    public init(erasureCodingDataStore: ErasureCodingDataStore?) {
        self.erasureCodingDataStore = erasureCodingDataStore
    }

    /// Purge old data from the data availability stores
    /// - Parameter epoch: The current epoch index
    public func purge(epoch: EpochIndex) async {
        // GP 14.3.1
        // Guarantors are required to erasure-code and distribute two data sets: one blob, the auditable work-package containing
        // the encoded work-package, extrinsic data and self-justifying imported segments which is placed in the short-term Audit
        // da store and a second set of exported-segments data together with the Paged-Proofs metadata. Items in the first store
        // are short-lived; assurers are expected to keep them only until finality of the block in which the availability of the work-
        // result's work-package is assured. Items in the second, meanwhile, are long-lived and expected to be kept for a minimum
        // of 28 days (672 complete epochs) following the reporting of the work-report.

        // Use ErasureCodingDataStore if available for efficient cleanup
        if let ecStore = erasureCodingDataStore {
            do {
                // Purge old audit store data (short-term storage, kept until finality, approximately 1 hour)
                // Assuming approximately 6 epochs per hour at 10 minutes per epoch
                let auditRetentionEpochs: EpochIndex = DataAvailabilityConstants.auditRetentionEpochs

                if epoch > auditRetentionEpochs {
                    let auditCutoffEpoch = epoch - auditRetentionEpochs
                    let (deleted, bytes) = try await ecStore.cleanupAuditEntriesBeforeEpoch(cutoffEpoch: auditCutoffEpoch)
                    logger.info("Purged \(deleted) audit entries (\(bytes) bytes) from epochs before \(auditCutoffEpoch)")
                }

                // Purge old import/D3L store data (long-term storage, kept for 28 days = 672 epochs)
                let d3lRetentionEpochs: EpochIndex = DataAvailabilityConstants.d3lRetentionEpochs

                if epoch > d3lRetentionEpochs {
                    let d3lCutoffEpoch = epoch - d3lRetentionEpochs
                    let (entriesDeleted, segmentsDeleted) = try await ecStore.cleanupD3LEntriesBeforeEpoch(cutoffEpoch: d3lCutoffEpoch)
                    logger.info("Purged \(entriesDeleted) D³L entries (\(segmentsDeleted) segments) from epochs before \(d3lCutoffEpoch)")
                }
            } catch {
                logger.error("Failed to purge old data: \(error)")
            }
        } else {
            // Fallback to timestamp-based approach for legacy DataStore
            // Assuming 1 hour for audit data, 28 days for D3L data
            let currentTimestamp = Date()
            let auditCutoffTime = currentTimestamp.addingTimeInterval(-3600) // 1 hour ago
            let d3lCutoffTime = currentTimestamp.addingTimeInterval(-28 * 24 * 3600) // 28 days ago

            // TODO: Implement timestamp-based cleanup when DataStore exposes iteration methods
            _ = (auditCutoffTime, d3lCutoffTime)
        }
    }

    /// Get cleanup metrics
    /// - Returns: Cleanup metrics if ErasureCodingDataStore is available
    public func getCleanupMetrics() async -> CleanupMetrics? {
        guard let ecStore = erasureCodingDataStore else {
            return nil
        }
        return await ecStore.getCleanupMetrics()
    }

    /// Reset cleanup metrics
    public func resetCleanupMetrics() async {
        await erasureCodingDataStore?.resetCleanupMetrics()
    }
}
