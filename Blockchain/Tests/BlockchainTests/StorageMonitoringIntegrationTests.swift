import Foundation

import Testing
import TracingUtils
import Utils

@testable import Blockchain

/// Integration tests for storage monitoring and cleanup
struct StorageMonitoringIntegrationTests {
    // MARK: - Storage Usage Tests

    @Test
    func storageUsageEmptyStore() async throws {
        // Test storage usage calculation for empty store
        let usage = StorageUsage(
            totalBytes: 0,
            auditStoreBytes: 0,
            d3lStoreBytes: 0,
            entryCount: 0,
            auditEntryCount: 0,
            d3lEntryCount: 0
        )

        #expect(usage.totalBytes == 0)
        #expect(usage.totalMB == 0.0)
        #expect(usage.auditStoreMB == 0.0)
        #expect(usage.d3lStoreMB == 0.0)
    }

    @Test
    func storageUsageWithAuditData() async throws {
        // Test storage usage with audit store data
        let bundleSize = 1_000_000 // 1 MB bundle
        let shardCount = 1023
        let shardBytes = shardCount * 684 // ~700 KB

        let usage = StorageUsage(
            totalBytes: bundleSize + shardBytes,
            auditStoreBytes: bundleSize + shardBytes,
            d3lStoreBytes: 0,
            entryCount: 1,
            auditEntryCount: 1,
            d3lEntryCount: 0
        )

        #expect(usage.totalBytes == bundleSize + shardBytes)
        #expect(usage.auditStoreBytes == bundleSize + shardBytes)
        #expect(usage.d3lStoreBytes == 0)
        #expect(usage.entryCount == 1)
        #expect(usage.auditEntryCount == 1)

        let expectedMB = Double(bundleSize + shardBytes) / (1024 * 1024)
        #expect(abs(usage.totalMB - expectedMB) < 0.01)
    }

    @Test
    func storageUsageWithD3LData() async throws {
        // Test storage usage with D³L store data
        let segmentCount = 1000
        let segmentBytes = segmentCount * 4104 // ~4 MB

        let usage = StorageUsage(
            totalBytes: segmentBytes,
            auditStoreBytes: 0,
            d3lStoreBytes: segmentBytes,
            entryCount: 1,
            auditEntryCount: 0,
            d3lEntryCount: 1
        )

        #expect(usage.totalBytes == segmentBytes)
        #expect(usage.auditStoreBytes == 0)
        #expect(usage.d3lStoreBytes == segmentBytes)
        #expect(usage.d3lEntryCount == 1)

        let expectedMB = Double(segmentBytes) / (1024 * 1024)
        #expect(abs(usage.d3lStoreMB - expectedMB) < 0.01)
    }

    @Test
    func storageUsageCombined() async throws {
        // Test storage usage with both audit and D³L data
        let auditBytes = 10_000_000 // 10 MB
        let d3lBytes = 50_000_000 // 50 MB

        let usage = StorageUsage(
            totalBytes: auditBytes + d3lBytes,
            auditStoreBytes: auditBytes,
            d3lStoreBytes: d3lBytes,
            entryCount: 100,
            auditEntryCount: 50,
            d3lEntryCount: 50
        )

        #expect(usage.totalBytes == auditBytes + d3lBytes)
        #expect(usage.auditStoreBytes == auditBytes)
        #expect(usage.d3lStoreBytes == d3lBytes)
        #expect(usage.entryCount == 100)

        let totalMB = Double(auditBytes + d3lBytes) / (1024 * 1024)
        #expect(abs(usage.totalMB - totalMB) < 0.01)
    }

    // MARK: - Storage Pressure Tests

    @Test
    func storagePressureNormal() async throws {
        // Test normal storage pressure (< 70%)
        let usage = StorageUsage(
            totalBytes: 600_000_000, // 600 MB
            auditStoreBytes: 200_000_000,
            d3lStoreBytes: 400_000_000,
            entryCount: 100,
            auditEntryCount: 50,
            d3lEntryCount: 50
        )

        let maxBytes = 1_000_000_000 // 1 GB
        let pressure = StoragePressure.from(usage: usage, maxBytes: maxBytes)

        #expect(pressure == .normal)
    }

    @Test
    func storagePressureWarning() async throws {
        // Test warning storage pressure (70-85%)
        let usage = StorageUsage(
            totalBytes: 750_000_000, // 750 MB = 75%
            auditStoreBytes: 250_000_000,
            d3lStoreBytes: 500_000_000,
            entryCount: 100,
            auditEntryCount: 50,
            d3lEntryCount: 50
        )

        let maxBytes = 1_000_000_000 // 1 GB
        let pressure = StoragePressure.from(usage: usage, maxBytes: maxBytes)

        #expect(pressure == .warning)
    }

    @Test
    func storagePressureCritical() async throws {
        // Test critical storage pressure (85-95%)
        let usage = StorageUsage(
            totalBytes: 900_000_000, // 900 MB = 90%
            auditStoreBytes: 300_000_000,
            d3lStoreBytes: 600_000_000,
            entryCount: 100,
            auditEntryCount: 50,
            d3lEntryCount: 50
        )

        let maxBytes = 1_000_000_000 // 1 GB
        let pressure = StoragePressure.from(usage: usage, maxBytes: maxBytes)

        #expect(pressure == .critical)
    }

    @Test
    func storagePressureEmergency() async throws {
        // Test emergency storage pressure (> 95%)
        let usage = StorageUsage(
            totalBytes: 980_000_000, // 980 MB = 98%
            auditStoreBytes: 330_000_000,
            d3lStoreBytes: 650_000_000,
            entryCount: 100,
            auditEntryCount: 50,
            d3lEntryCount: 50
        )

        let maxBytes = 1_000_000_000 // 1 GB
        let pressure = StoragePressure.from(usage: usage, maxBytes: maxBytes)

        #expect(pressure == .emergency)
    }

    @Test
    func storagePressureBoundaryValues() async throws {
        // Test boundary values for storage pressure levels

        // Exactly 70% - should be warning (>= 70%)
        let usage70 = StorageUsage(
            totalBytes: 700_000_000,
            auditStoreBytes: 0,
            d3lStoreBytes: 700_000_000,
            entryCount: 10,
            auditEntryCount: 0,
            d3lEntryCount: 10
        )
        #expect(StoragePressure.from(usage: usage70, maxBytes: 1_000_000_000) == .warning)

        // Exactly 85% - should be critical (>= 85%)
        let usage85 = StorageUsage(
            totalBytes: 850_000_000,
            auditStoreBytes: 0,
            d3lStoreBytes: 850_000_000,
            entryCount: 10,
            auditEntryCount: 0,
            d3lEntryCount: 10
        )
        #expect(StoragePressure.from(usage: usage85, maxBytes: 1_000_000_000) == .critical)

        // Exactly 95% - should be emergency (>= 95%)
        let usage95 = StorageUsage(
            totalBytes: 950_000_000,
            auditStoreBytes: 0,
            d3lStoreBytes: 950_000_000,
            entryCount: 10,
            auditEntryCount: 0,
            d3lEntryCount: 10
        )
        #expect(StoragePressure.from(usage: usage95, maxBytes: 1_000_000_000) == .emergency)
    }

    // MARK: - Incremental Cleanup Tests

    @Test
    func incrementalCleanupProgress() async throws {
        // Test incremental cleanup progress calculation
        let progress = IncrementalCleanupProgress(
            totalEntries: 1000,
            processedEntries: 250,
            remainingEntries: 750,
            bytesReclaimed: 250_000_000,
            isComplete: false
        )

        #expect(progress.totalEntries == 1000)
        #expect(progress.processedEntries == 250)
        #expect(progress.remainingEntries == 750)
        #expect(progress.bytesReclaimed == 250_000_000)
        #expect(progress.isComplete == false)
        #expect(abs(progress.progress - 0.25) < 0.001)
    }

    @Test
    func incrementalCleanupProgressComplete() async throws {
        // Test incremental cleanup when complete
        let progress = IncrementalCleanupProgress(
            totalEntries: 100,
            processedEntries: 100,
            remainingEntries: 0,
            bytesReclaimed: 100_000_000,
            isComplete: true
        )

        #expect(progress.totalEntries == 100)
        #expect(progress.processedEntries == 100)
        #expect(progress.remainingEntries == 0)
        #expect(progress.isComplete == true)
        #expect(progress.progress == 1.0)
    }

    @Test
    func incrementalCleanupProgressEmpty() async throws {
        // Test incremental cleanup with no entries
        let progress = IncrementalCleanupProgress(
            totalEntries: 0,
            processedEntries: 0,
            remainingEntries: 0,
            bytesReclaimed: 0,
            isComplete: true
        )

        #expect(progress.totalEntries == 0)
        #expect(progress.processedEntries == 0)
        #expect(progress.remainingEntries == 0)
        #expect(progress.bytesReclaimed == 0)
        #expect(progress.isComplete == true)
        #expect(progress.progress == 1.0)
    }

    @Test
    func incrementalCleanupProgressPartial() async throws {
        // Test incremental cleanup progress at various stages
        let stages = [
            (0, 1000, 0.0),
            (250, 750, 0.25),
            (500, 500, 0.5),
            (750, 250, 0.75),
            (1000, 0, 1.0),
        ]

        for (processed, remaining, expectedProgress) in stages {
            let progress = IncrementalCleanupProgress(
                totalEntries: 1000,
                processedEntries: processed,
                remainingEntries: remaining,
                bytesReclaimed: processed * 1_000_000,
                isComplete: processed == 1000
            )

            #expect(abs(progress.progress - expectedProgress) < 0.001)
        }
    }

    // MARK: - Reconstruction Plan Tests

    @Test
    func reconstructionPlanCanReconstructLocally() async throws {
        // Test reconstruction plan when local reconstruction is possible
        let plan = ReconstructionPlan(
            erasureRoot: Data32([1; 32]),
            localShards: 400,
            missingShards: 623,
            canReconstructLocally: true,
            reconstructionPercentage: 116.96 // 400/342*100
        )

        #expect(plan.localShards == 400)
        #expect(plan.missingShards == 623)
        #expect(plan.canReconstructLocally == true)
        #expect(plan.needsNetworkFetch == false)
        #expect(plan.estimatedTimeToFetch == nil)
    }

    @Test
    func reconstructionPlanNeedsNetworkFetch() async throws {
        // Test reconstruction plan when network fetch is needed
        let plan = ReconstructionPlan(
            erasureRoot: Data32([1; 32]),
            localShards: 300,
            missingShards: 723,
            canReconstructLocally: false,
            reconstructionPercentage: 87.72 // 300/342*100
        )

        #expect(plan.localShards == 300)
        #expect(plan.missingShards == 723)
        #expect(plan.canReconstructLocally == false)
        #expect(plan.needsNetworkFetch == true)

        // Estimated time: 723 * 0.1s = 72.3s
        let estimatedTime = plan.estimatedTimeToFetch
        #expect(estimatedTime != nil)
        if let estimatedTime {
            #expect(abs(estimatedTime - 72.3) < 1.0)
        }
    }

    @Test
    func reconstructionPlanExactThreshold() async throws {
        // Test reconstruction plan at exact threshold
        let plan = ReconstructionPlan(
            erasureRoot: Data32([1; 32]),
            localShards: 342,
            missingShards: 681,
            canReconstructLocally: true,
            reconstructionPercentage: 100.0
        )

        #expect(plan.localShards == 342)
        #expect(plan.canReconstructLocally == true)
        #expect(plan.reconstructionPercentage == 100.0)
    }

    @Test
    func reconstructionPlanZeroLocalShards() async throws {
        // Test reconstruction plan with no local shards
        let plan = ReconstructionPlan(
            erasureRoot: Data32([1; 32]),
            localShards: 0,
            missingShards: 1023,
            canReconstructLocally: false,
            reconstructionPercentage: 0.0
        )

        #expect(plan.localShards == 0)
        #expect(plan.missingShards == 1023)
        #expect(plan.canReconstructLocally == false)
        #expect(plan.reconstructionPercentage == 0.0)

        // Estimated time: 1023 * 0.1s = 102.3s
        let estimatedTime = plan.estimatedTimeToFetch
        #expect(estimatedTime != nil)
        if let estimatedTime {
            #expect(abs(estimatedTime - 102.3) < 1.0)
        }
    }

    @Test
    func reconstructionPlanAllLocalShards() async throws {
        // Test reconstruction plan with all local shards
        let plan = ReconstructionPlan(
            erasureRoot: Data32([1; 32]),
            localShards: 1023,
            missingShards: 0,
            canReconstructLocally: true,
            reconstructionPercentage: 299.12 // 1023/342*100, capped at 100
        )

        #expect(plan.localShards == 1023)
        #expect(plan.missingShards == 0)
        #expect(plan.canReconstructLocally == true)
        #expect(plan.needsNetworkFetch == false)
        #expect(plan.estimatedTimeToFetch == nil)
    }

    // MARK: - Storage Size Conversion Tests

    @Test
    func byteToMBConversion() async throws {
        // Test byte to MB conversion accuracy
        let testCases: [(Int, Double)] = [
            (0, 0.0),
            (1_048_576, 1.0), // Exactly 1 MB
            (10_485_760, 10.0), // 10 MB
            (104_857_600, 100.0), // 100 MB
            (1_073_741_824, 1024.0), // 1 GB
            (500_000, 0.477), // ~0.5 MB
        ]

        for (bytes, expectedMB) in testCases {
            let usage = StorageUsage(
                totalBytes: bytes,
                auditStoreBytes: bytes,
                d3lStoreBytes: 0,
                entryCount: 1,
                auditEntryCount: 1,
                d3lEntryCount: 0
            )

            let actualMB = usage.totalMB
            let tolerance = max(0.01, expectedMB * 0.001) // 0.1% tolerance
            #expect(abs(actualMB - expectedMB) < tolerance, "Bytes: \(bytes), Expected: \(expectedMB), Got: \(actualMB)")
        }
    }

    // MARK: - Data Availability Error Tests

    @Test
    func insufficientShardsError() async throws {
        // Test insufficient shards error
        let error = DataAvailabilityError.insufficientShards(available: 100, required: 342)

        switch error {
        case let .insufficientShards(available, required):
            #expect(available == 100)
            #expect(required == 342)
        default:
            Issue.record("Expected insufficientShards error")
        }
    }

    @Test
    func segmentNotFoundError() async throws {
        // Test segment not found error
        let error = DataAvailabilityError.segmentNotFound

        switch error {
        case .segmentNotFound:
            // Expected
            break
        default:
            Issue.record("Expected segmentNotFound error")
        }
    }

    @Test
    func bundleTooLargeError() async throws {
        // Test bundle too large error
        let error = DataAvailabilityError.bundleTooLarge(size: 20_000_000, maxSize: 13_791_360)

        switch error {
        case let .bundleTooLarge(size, maxSize):
            #expect(size == 20_000_000)
            #expect(maxSize == 13_791_360)
        default:
            Issue.record("Expected bundleTooLarge error")
        }
    }
}
