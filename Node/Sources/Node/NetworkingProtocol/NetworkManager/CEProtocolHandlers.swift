import Blockchain
import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "CEProtocolHandlers")

// MARK: - CE Protocol Handlers

/// Handles Common Ephemeral (CE) protocol requests
///
/// Stateless struct for thread-safe protocol handling
public struct CEProtocolHandlers: Sendable {
    private let blockchain: Blockchain

    public init(blockchain: Blockchain) {
        self.blockchain = blockchain
    }

    /// Main handler - routes to specific protocol handlers
    ///
    /// - Parameter ceRequest: The CE request to handle
    /// - Returns: Response data
    /// - Throws: Network errors or encoding errors
    public func handle(ceRequest: CERequest) async throws -> [Data] {
        logger.trace("handling request", metadata: ["request": "\(ceRequest)"])
        switch ceRequest {
        case let .blockRequest(message):
            return try await handleBlockRequest(message)
        case let .stateRequest(message):
            return await handleStateRequest(message)
        case let .safroleTicket1(message):
            return await handleSafroleTicket1(message)
        case let .safroleTicket2(message):
            return await handleSafroleTicket2(message)
        case let .workPackageSubmission(message):
            return await handleWorkPackageSubmission(message)
        case let .workPackageSharing(message):
            return try await handleWorkPackageSharing(message)
        case let .workReportDistribution(message):
            return try await handleWorkReportDistribution(message)
        case let .workReportRequest(message):
            return try await handleWorkReportRequest(message)
        case let .shardDistribution(message):
            return try await handleShardDistribution(message)
        case let .auditShardRequest(message):
            return await handleAuditShardRequest(message)
        case let .segmentShardRequest1(message):
            return await handleSegmentShardRequest1(message)
        case let .segmentShardRequest2(message):
            return await handleSegmentShardRequest2(message)
        case let .assuranceDistribution(message):
            return await handleAssuranceDistribution(message)
        case let .preimageAnnouncement(message):
            return await handlePreimageAnnouncement(message)
        case let .preimageRequest(message):
            return await handlePreimageRequest(message)
        case let .auditAnnouncement(message):
            return await handleAuditAnnouncement(message)
        case let .judgementPublication(message):
            return await handleJudgementPublication(message)
        case let .workPackageBundleSubmission(message):
            return await handleWorkPackageBundleSubmission(message)
        }
    }

    // MARK: - Block Request

    private func handleBlockRequest(_ message: BlockRequest) async throws -> [Data] {
        let dataProvider = blockchain.dataProvider
        let count = min(MAX_BLOCKS_PER_REQUEST, message.maxBlocks)
        let encoder = JamEncoder()

        switch message.direction {
        case .ascendingExcludsive:
            let number = try await dataProvider.getBlockNumber(hash: message.hash)
            var currentHash = message.hash

            for i in 1 ... count {
                let hashes = try await dataProvider.getBlockHash(byNumber: number + i)
                var found = false

                for hash in hashes {
                    let block = try await dataProvider.getBlock(hash: hash)
                    if block.header.parentHash == currentHash {
                        try encoder.encode(block)
                        found = true
                        currentHash = hash
                        break
                    }
                }

                if !found {
                    break
                }
            }

        case .descendingInclusive:
            var hash = message.hash

            for _ in 0 ..< count {
                let block = try await dataProvider.getBlock(hash: hash)
                try encoder.encode(block)

                if hash == dataProvider.genesisBlockHash {
                    break
                }

                hash = block.header.parentHash
            }
        }

        return [encoder.data]
    }

    // MARK: - State Request

    private func handleStateRequest(_ message: StateRequest) async -> [Data] {
        // Publish state request event
        blockchain.publish(
            event: RuntimeEvents.StateRequestReceived(
                headerHash: message.headerHash,
                startKey: message.startKey,
                endKey: message.endKey,
                maxSize: message.maxSize,
            ),
        )

        // Wait for response with timeout
        do {
            let requestId = try JamEncoder.encode(
                message.headerHash,
                message.startKey,
                message.endKey,
                message.maxSize,
            ).blake2b256hash()

            let response = try await blockchain.waitFor(
                RuntimeEvents.StateRequestReceivedResponse.self,
                check: { $0.requestId == requestId },
                timeout: 5.0,
            )

            // Return the key-value pairs as response
            switch response.result {
            case let .success((_, _, keyValuePairs)):
                // Encode the key-value pairs
                let encoder = JamEncoder()
                try encoder.encode(UInt32(keyValuePairs.count))
                for (key, value) in keyValuePairs {
                    try encoder.encode(key)
                    try encoder.encode(Data(value))
                }
                return [encoder.data]

            case let .failure(error):
                return handleRequestError(error, messageType: "State request")
            }
        } catch {
            logger.warning("State request timed out or failed: \(error)")
            return []
        }
    }

    // MARK: - Safrole Tickets

    private func handleSafroleTicket1(_ message: SafroleTicketMessage) async -> [Data] {
        blockchain.publish(event: RuntimeEvents.SafroleTicketsReceived(
            items: [
                ExtrinsicTickets.TicketItem(
                    attempt: message.attempt,
                    signature: message.proof,
                ),
            ],
        ))
        // TODO: rebroadcast to other peers after some time
        return []
    }

    private func handleSafroleTicket2(_ message: SafroleTicketMessage) async -> [Data] {
        blockchain.publish(event: RuntimeEvents.SafroleTicketsReceived(
            items: [
                ExtrinsicTickets.TicketItem(
                    attempt: message.attempt,
                    signature: message.proof,
                ),
            ],
        ))
        return []
    }

    // MARK: - Work Package

    private func handleWorkPackageSubmission(_ message: WorkPackageSubmissionMessage) async -> [Data] {
        blockchain
            .publish(
                event: RuntimeEvents
                    .WorkPackagesReceived(
                        coreIndex: message.coreIndex,
                        workPackage: message.workPackage.asRef(),
                        extrinsics: message.extrinsics,
                    ),
            )
        return []
    }

    private func handleWorkPackageSharing(_ message: WorkPackageSharingMessage) async throws -> [Data] {
        let hash = message.bundle.hash()
        blockchain
            .publish(
                event: RuntimeEvents
                    .WorkPackageBundleReceived(
                        coreIndex: message.coreIndex,
                        bundle: message.bundle,
                        segmentsRootMappings: message.segmentsRootMappings,
                    ),
            )

        let resp = try await blockchain.waitFor(RuntimeEvents.WorkPackageBundleReceivedResponse.self) { event in
            hash == event.workBundleHash
        }
        let (workReportHash, signature) = try resp.result.get()
        return try [JamEncoder.encode(workReportHash, signature)]
    }

    // MARK: - Work Report

    private func handleWorkReportDistribution(_ message: WorkReportDistributionMessage) async throws -> [Data] {
        let hash = message.workReport.hash()
        blockchain
            .publish(
                event: RuntimeEvents
                    .WorkReportReceived(
                        workReport: message.workReport,
                        slot: message.slot,
                        signatures: message.signatures,
                    ),
            )

        let resp = try await blockchain.waitFor(RuntimeEvents.WorkReportReceivedResponse.self) { event in
            hash == event.workReportHash
        }
        _ = try resp.result.get()
        return []
    }

    private func handleWorkReportRequest(_ message: WorkReportRequestMessage) async throws -> [Data] {
        let workReportRef = try await blockchain.dataProvider.getGuaranteedWorkReport(hash: message.workReportHash)
        if let workReport = workReportRef {
            return try [JamEncoder.encode(workReport.value)]
        }
        return []
    }

    // MARK: - Shard Distribution

    private func handleShardDistribution(_ message: ShardDistributionMessage) async throws -> [Data] {
        let receivedEvent = RuntimeEvents.ShardDistributionReceived(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex,
        )
        let requestId = try receivedEvent.generateRequestId()

        blockchain.publish(event: receivedEvent)

        let resp = try await blockchain.waitFor(RuntimeEvents.ShardDistributionReceivedResponse.self) { event in
            requestId == event.requestId
        }
        let (bundleShard, segmentShards, justification) = try resp.result.get()
        return try [JamEncoder.encode(bundleShard, segmentShards, justification)]
    }

    // MARK: - Audit Shard Request

    private func handleAuditShardRequest(_ message: AuditShardRequestMessage) async -> [Data] {
        // Publish audit shard request event
        let receivedEvent = RuntimeEvents.AuditShardRequestReceived(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex,
        )
        blockchain.publish(event: receivedEvent)

        // Wait for response with timeout
        do {
            let requestId = try receivedEvent.generateRequestId()

            let response = try await blockchain.waitFor(
                RuntimeEvents.AuditShardRequestReceivedResponse.self,
                check: { $0.requestId == requestId },
                timeout: 5.0,
            )

            // Return the bundle shard and justification
            switch response.result {
            case let .success((_, _, bundleShard, justification)):
                return try [JamEncoder.encode(bundleShard, justification)]

            case let .failure(error):
                return handleRequestError(error, messageType: "Audit shard request")
            }
        } catch {
            logger.warning("Audit shard request timed out or failed: \(error)")
            return []
        }
    }

    // MARK: - Segment Shard Request

    private func handleSegmentShardRequest1(_ message: SegmentShardRequestMessage) async -> [Data] {
        // Publish segment shard request event
        let receivedEvent = RuntimeEvents.SegmentShardRequestReceived(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex,
            segmentIndices: message.segmentIndices,
        )
        blockchain.publish(event: receivedEvent)

        // Wait for response with timeout
        do {
            let requestId = try receivedEvent.generateRequestId()

            let response = try await blockchain.waitFor(
                RuntimeEvents.SegmentShardRequestReceivedResponse.self,
                check: { $0.requestId == requestId },
                timeout: 5.0,
            )

            // Return the segment shards
            switch response.result {
            case let .success(segmentShards):
                return try [JamEncoder.encode(segmentShards)]

            case let .failure(error):
                return handleRequestError(error, messageType: "Segment shard request")
            }
        } catch {
            logger.warning("Segment shard request timed out or failed: \(error)")
            return []
        }
    }

    private func handleSegmentShardRequest2(_ message: SegmentShardRequestMessage) async -> [Data] {
        // Publish segment shard request event
        let receivedEvent = RuntimeEvents.SegmentShardRequestReceived(
            erasureRoot: message.erasureRoot,
            shardIndex: message.shardIndex,
            segmentIndices: message.segmentIndices,
        )
        blockchain.publish(event: receivedEvent)

        // Wait for response with timeout
        do {
            let requestId = try receivedEvent.generateRequestId()

            let response = try await blockchain.waitFor(
                RuntimeEvents.SegmentShardRequestReceivedResponse.self,
                check: { $0.requestId == requestId },
                timeout: 5.0,
            )

            // Return the segment shards
            switch response.result {
            case let .success(segmentShards):
                return try [JamEncoder.encode(segmentShards)]

            case let .failure(error):
                return handleRequestError(error, messageType: "Segment shard request")
            }
        } catch {
            logger.warning("Segment shard request timed out or failed: \(error)")
            return []
        }
    }

    // MARK: - Assurance Distribution

    private func handleAssuranceDistribution(_ message: AssuranceDistributionMessage) async -> [Data] {
        blockchain
            .publish(
                event: RuntimeEvents
                    .AssuranceDistributionReceived(
                        headerHash: message.headerHash,
                        bitfield: message.bitfield,
                        signature: message.signature,
                    ),
            )
        return []
    }

    // MARK: - Preimage

    private func handlePreimageAnnouncement(_ message: PreimageAnnouncementMessage) async -> [Data] {
        blockchain
            .publish(
                event: RuntimeEvents
                    .PreimageAnnouncementReceived(
                        serviceID: message.serviceID,
                        hash: message.hash,
                        preimageLength: message.preimageLength,
                    ),
            )
        return []
    }

    private func handlePreimageRequest(_ message: PreimageRequestMessage) async -> [Data] {
        // Publish preimage request event
        blockchain.publish(event: RuntimeEvents.PreimageRequestReceived(hash: message.hash))

        // Wait for response with timeout
        do {
            let response = try await blockchain.waitFor(
                RuntimeEvents.PreimageRequestReceivedResponse.self,
                check: { $0.hash == message.hash },
                timeout: 5.0,
            )

            // Return the preimage
            switch response.result {
            case let .success(preimage):
                return try [JamEncoder.encode(preimage)]

            case let .failure(error):
                return handleRequestError(error, messageType: "Preimage request")
            }
        } catch {
            logger.warning("Preimage request timed out or failed: \(error)")
            return []
        }
    }

    // MARK: - Audit Announcement

    private func handleAuditAnnouncement(_ message: AuditAnnouncementMessage) async -> [Data] {
        blockchain
            .publish(
                event: RuntimeEvents
                    .AuditAnnouncementReceived(
                        headerHash: message.headerHash,
                        tranche: message.tranche,
                        announcement: message.announcement,
                        evidence: message.evidence,
                    ),
            )
        return []
    }

    // MARK: - Judgement Publication

    private func handleJudgementPublication(_ message: JudgementPublicationMessage) async -> [Data] {
        blockchain
            .publish(
                event: RuntimeEvents
                    .JudgementPublicationReceived(
                        epochIndex: message.epochIndex,
                        validatorIndex: message.validatorIndex,
                        validity: message.validity,
                        workReportHash: message.workReportHash,
                        signature: message.signature,
                    ),
            )
        return []
    }

    // MARK: - Work Package Bundle Submission

    private func handleWorkPackageBundleSubmission(_ message: WorkPackageBundleSubmissionMessage) async -> [Data] {
        // TODO: Implement work package bundle submission handler
        // No corresponding RuntimeEvent exists yet
        logger.debug("Received work package bundle submission from core \(message.coreIndex)")
        return []
    }
}
