import Blockchain
import Database
import Foundation
import Testing
import TracingUtils
import Utils

@testable import Node

final class NodeTests {
    let path = {
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent("\(UUID().uuidString)")
    }()

    func getDatabase(_ index: Int) -> Database {
        Database.rocksDB(path: path.appendingPathComponent("\(index)"))
    }

    deinit {
        try? FileManager.default.removeItem(at: path)
    }

    @Test func validatorNodeInMemory() async throws {
        let (nodes, scheduler) = try await Topology(
            nodes: [NodeDescription(isValidator: true)]
        ).build(genesis: .preset(.minimal))

        let (validatorNode, storeMiddlware) = nodes[0]

        // Get initial state
        let initialBestHead = await validatorNode.dataProvider.bestHead
        let initialTimeslot = initialBestHead.timeslot

        // Advance time
        for _ in 0 ..< 10 {
            await scheduler.advance(
                by: TimeInterval(validatorNode.blockchain.config.value.slotPeriodSeconds)
            )
            await storeMiddlware.wait()
        }

        // Wait for block production
        try await Task.sleep(for: .milliseconds(500))

        // Get new state
        let newBestHead = await validatorNode.dataProvider.bestHead
        let newTimeslot = newBestHead.timeslot

        // Verify block was produced
        #expect(newTimeslot > initialTimeslot)
        #expect(try await validatorNode.blockchain.dataProvider.hasBlock(hash: newBestHead.hash))
    }

    @Test func validatorNodeRocksDB() async throws {
        let (nodes, scheduler) = try await Topology(
            nodes: [NodeDescription(isValidator: true, database: getDatabase(0))]
        ).build(genesis: .preset(.minimal))

        let (validatorNode, storeMiddlware) = nodes[0]

        // Get initial state
        let initialBestHead = await validatorNode.dataProvider.bestHead
        let initialTimeslot = initialBestHead.timeslot

        // Advance time
        for _ in 0 ..< 10 {
            await scheduler.advance(
                by: TimeInterval(validatorNode.blockchain.config.value.slotPeriodSeconds)
            )
            await storeMiddlware.wait()
        }

        // Wait for block production
        try await Task.sleep(for: .milliseconds(500))

        // Get new state
        let newBestHead = await validatorNode.dataProvider.bestHead
        let newTimeslot = newBestHead.timeslot

        // Verify block was produced
        #expect(newTimeslot > initialTimeslot)
        #expect(try await validatorNode.blockchain.dataProvider.hasBlock(hash: newBestHead.hash))
        #expect(try await validatorNode.blockchain.dataProvider.getKeys(prefix: Data(), count: 0, startKey: nil, blockHash: nil).isEmpty)
        await #expect(throws: StateBackendError.self) {
            _ = try await validatorNode.blockchain.dataProvider.getStorage(key: Data31.random(), blockHash: nil)
        }
        let guaranteedWorkReport = GuaranteedWorkReport.dummy(config: .dev)
        let hash = guaranteedWorkReport.workReport.hash()
        try await validatorNode.blockchain.dataProvider.add(guaranteedWorkReport: GuaranteedWorkReportRef(guaranteedWorkReport))
        #expect(try await (validatorNode.blockchain.dataProvider.getGuaranteedWorkReport(hash: hash)) != nil)
        #expect(try await validatorNode.blockchain.dataProvider.hasGuaranteedWorkReport(hash: hash) == true)
    }

    @Test func sync() async throws {
        // Create validator and full node
        let (nodes, scheduler) = try await Topology(
            nodes: [
                NodeDescription(isValidator: true, database: getDatabase(0)),
                NodeDescription(devSeed: 1, database: getDatabase(1)),
            ],
            connections: [(0, 1)]
        ).build(genesis: .preset(.minimal))

        let (validatorNode, validatorStoreMiddlware) = nodes[0]
        let (node, nodeStoreMiddlware) = nodes[1]

        // Advance time to produce blocks
        for _ in 0 ..< 10 {
            await scheduler.advance(
                by: TimeInterval(validatorNode.blockchain.config.value.slotPeriodSeconds)
            )
            await validatorStoreMiddlware.wait()
            await nodeStoreMiddlware.wait()

            // Add a small delay to ensure block production completes before next advance
            try await Task.sleep(for: .milliseconds(100))
        }

        // Wait for sync
        try await Task.sleep(for: .milliseconds(500))

        // Verify sync
        let validatorBestHead = await validatorNode.dataProvider.bestHead
        let nodeBestHead = await node.dataProvider.bestHead

        #expect(validatorBestHead.hash == nodeBestHead.hash)

        // Produce more blocks
        for _ in 0 ..< 10 {
            await scheduler.advance(
                by: TimeInterval(validatorNode.blockchain.config.value.slotPeriodSeconds)
            )
            await validatorStoreMiddlware.wait()
            await nodeStoreMiddlware.wait()

            // Add a small delay to ensure block production completes before next advance
            try await Task.sleep(for: .milliseconds(100))
        }

        try await Task.sleep(for: .milliseconds(500))

        await validatorStoreMiddlware.wait()
        await nodeStoreMiddlware.wait()

        // Verify new blocks are synced
        let newValidatorBestHead = await validatorNode.dataProvider.bestHead
        let newNodeBestHead = await node.dataProvider.bestHead

        #expect(newValidatorBestHead.hash == newNodeBestHead.hash)
        #expect(newValidatorBestHead.timeslot > validatorBestHead.timeslot)
    }

    @Test func multiplePeers() async throws {
        // Create multiple nodes
        var nodeDescriptions: [NodeDescription] = [
            NodeDescription(isValidator: true, database: getDatabase(0)),
            NodeDescription(isValidator: true, devSeed: 1, database: getDatabase(1)),
        ]
        // Add 18 non-validator nodes
        for i in 2 ... 19 {
            nodeDescriptions.append(NodeDescription(devSeed: UInt32(i), database: getDatabase(i)))
        }

        let (nodes, scheduler) = try await Topology(
            nodes: nodeDescriptions,
            connections: (0 ..< 20).flatMap { i in
                (i + 1 ..< 20).map { j in (i, j) } // Fully connected topology
            }
        ).build(genesis: .preset(.minimal))

        let (validator1, validator1StoreMiddlware) = nodes[0]
        let (validator2, validator2StoreMiddlware) = nodes[1]
        #expect(validator1.network.network.peerRole == .validator)
        #expect(validator1.network.network.networkKey != "")
        // Extract non-validator nodes and their middleware
        let nonValidatorNodes = nodes[2...].map(\.self)

        try await Task.sleep(for: .milliseconds(nodes.count * 100))
        let (node1, _) = nonValidatorNodes[0]
        let (node2, _) = nonValidatorNodes[1]
        // Verify connections for a sample of non-validator nodes
        #expect(node1.network.peersCount == 19)
        #expect(node2.network.peersCount == 19)
        // Advance time to produce blocks
        for _ in 0 ..< 20 {
            await scheduler.advance(
                by: TimeInterval(validator1.blockchain.config.value.slotPeriodSeconds)
            )
            await validator1StoreMiddlware.wait()
            await validator2StoreMiddlware.wait()

            for (_, middleware) in nonValidatorNodes {
                await middleware.wait()
            }
        }
        try await Task.sleep(for: .milliseconds(nodes.count * 100))
        let validator1BestHead = await validator1.dataProvider.bestHead
        let validator2BestHead = await validator2.dataProvider.bestHead

        for (node, _) in nonValidatorNodes {
            let nodeBestHead = await node.dataProvider.bestHead
            #expect(validator1BestHead.hash == nodeBestHead.hash)
            #expect(validator2BestHead.hash == nodeBestHead.hash)
        }
    }

    @Test
    func moreMultiplePeers() async throws {
        var nodeDescriptions: [NodeDescription] = [
            NodeDescription(isValidator: true, database: getDatabase(0)),
            NodeDescription(isValidator: true, devSeed: 1, database: getDatabase(1)),
        ]

        for i in 2 ..< 20 {
            nodeDescriptions.append(NodeDescription(devSeed: UInt32(i), database: .inMemory))
        }

        let connections = (0 ..< 20).map { i in
            let next = (i + 1) % 20
            return (i, next)
        }

        let (nodes, scheduler) = try await Topology(
            nodes: nodeDescriptions,
            connections: connections
        ).build(genesis: .preset(.minimal))

        let (validator1, _) = nodes[0]
        let (validator2, _) = nodes[1]
        let nonValidatorNodes = nodes[2...]

        var allSynced = false
        let maxIterations = 100

        for _ in 0 ..< 5 {
            await scheduler.advance(
                by: TimeInterval(validator1.blockchain.config.value.slotPeriodSeconds)
            )
            for (_, middleware) in nodes {
                await middleware.wait()
            }
        }

        try await Task.sleep(for: .milliseconds(nodes.count * 200))

        for _ in 0 ..< maxIterations {
            let validator1Head = await validator1.dataProvider.bestHead
            let validator2Head = await validator2.dataProvider.bestHead

            guard validator1Head.hash == validator2Head.hash else {
                try await Task.sleep(for: .milliseconds(500))
                continue
            }

            allSynced = try await withThrowingTaskGroup(of: Bool.self) { group in
                for (node, _) in nonValidatorNodes {
                    group.addTask { [dataProvider = node.dataProvider] in
                        let nodeBestHead = await dataProvider.bestHead
                        return nodeBestHead.hash == validator1Head.hash
                    }
                }
                let results = try await group.reduce(into: [Bool]()) { $0.append($1) }
                return results.allSatisfy(\.self)
            }

            if allSynced {
                break
            }
            for (_, middleware) in nodes {
                await middleware.wait()
            }
        }

        #expect(allSynced == true)
    }
}
