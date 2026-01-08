import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "AvailabilityVerification")

/// Service for verifying data availability of work packages
///
/// Checks if work packages are available locally and provides detailed
/// availability status information
public actor AvailabilityVerification {
    private let dataStore: DataStore

    public init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    /// Verify that a work package is available
    /// - Parameter workPackageHash: The hash of the work package to verify
    /// - Returns: True if the work package is available
    public func isWorkPackageAvailable(workPackageHash: Data32) async -> Bool {
        do {
            // Check if we have the segments root for this work package
            // Note: DataStore doesn't expose getSegmentRoot directly, so we try fetching a segment
            // If we can resolve the segment root, the work package is available
            let segment = WorkItem.ImportedDataSegment(
                root: .workPackageHash(workPackageHash),
                index: 0
            )
            let result = try await dataStore.fetchSegment(segments: [segment], segmentsRootMappings: nil)
            return !result.isEmpty
        } catch {
            logger.error("Failed to check work package availability: \(error)")
            return false
        }
    }

    /// Get the availability status of a work package
    /// - Parameter workPackageHash: The hash of the work package
    /// - Returns: The availability status including segments root and shard count
    public func getWorkPackageAvailabilityStatus(workPackageHash: Data32) async
        -> (available: Bool, segmentsRoot: Data32?, shardCount: Int?)
    {
        do {
            // Try to fetch a segment to check availability
            let segment = WorkItem.ImportedDataSegment(
                root: .workPackageHash(workPackageHash),
                index: 0
            )
            let result = try await dataStore.fetchSegment(segments: [segment], segmentsRootMappings: nil)

            if !result.isEmpty {
                // TODO: Get actual segments root and shard count when DataStore supports it
                return (true, nil, nil)
            }

            return (false, nil, nil)
        } catch {
            logger.error("Failed to get work package availability status: \(error)")
            return (false, nil, nil)
        }
    }

    /// Verify data availability for multiple work packages
    /// - Parameter workPackageHashes: The hashes of the work packages to verify
    /// - Returns: Dictionary mapping work package hash to availability status
    public func verifyMultipleWorkPackagesAvailability(
        workPackageHashes: [Data32]
    ) async -> [Data32: Bool] {
        var results: [Data32: Bool] = [:]

        await withTaskGroup(of: (Data32, Bool).self) { group in
            for hash in workPackageHashes {
                group.addTask {
                    let available = await self.isWorkPackageAvailable(workPackageHash: hash)
                    return (hash, available)
                }
            }

            for await (hash, available) in group {
                results[hash] = available
            }
        }

        return results
    }
}
