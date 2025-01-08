import Blockchain
import Foundation
import Testing
import Utils

@testable import Node

final class NodeTests {
    let path = {
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent("\(UUID().uuidString)")
    }()

    func getDatabase(_ idx: Int) -> Database {
        Database.rocksDB(path: path.appendingPathComponent("\(idx)"))
    }

    deinit {
        try? FileManager.default.removeItem(at: path)
    }

    @Test
    func validatorNodeInMemory() async throws {
        let (nodes, scheduler) = try await Topology(
            nodes: [NodeDescription(isValidator: true)]
        ).build(genesis: .preset(.minimal))

        let (validatorNode, storeMiddlware) = nodes[0]

        // Get initial state
        let initialBestHead = await validatorNode.dataProvider.bestHead
        let initialTimeslot = initialBestHead.timeslot

        // Advance time
        for _ in 0 ..< 10 {
            await scheduler.advance(by: TimeInterval(validatorNode.blockchain.config.value.slotPeriodSeconds))
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

    @Test
    func validatorNodeRocksDB() async throws {
        let (nodes, scheduler) = try await Topology(
            nodes: [NodeDescription(isValidator: true, database: getDatabase(0))]
        ).build(genesis: .preset(.minimal))

        let (validatorNode, storeMiddlware) = nodes[0]

        // Get initial state
        let initialBestHead = await validatorNode.dataProvider.bestHead
        let initialTimeslot = initialBestHead.timeslot

        // Advance time
        for _ in 0 ..< 10 {
            await scheduler.advance(by: TimeInterval(validatorNode.blockchain.config.value.slotPeriodSeconds))
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

    @Test
    func sync() async throws {
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
            await scheduler.advance(by: TimeInterval(validatorNode.blockchain.config.value.slotPeriodSeconds))
            await validatorStoreMiddlware.wait()
            await nodeStoreMiddlware.wait()
        }

        // Wait for sync
        try await Task.sleep(for: .milliseconds(500))

        // Verify sync
        let validatorBestHead = await validatorNode.dataProvider.bestHead
        let nodeBestHead = await node.dataProvider.bestHead

        #expect(validatorBestHead.hash == nodeBestHead.hash)

        // Produce more blocks
        for _ in 0 ..< 10 {
            await scheduler.advance(by: TimeInterval(validatorNode.blockchain.config.value.slotPeriodSeconds))
            await validatorStoreMiddlware.wait()
            await nodeStoreMiddlware.wait()
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

    @Test
    func multiplePeers() async throws {
        // Create multiple nodes
        let (nodes, scheduler) = try await Topology(
            nodes: [
                NodeDescription(isValidator: true, database: getDatabase(0)),
                NodeDescription(isValidator: true, devSeed: 1, database: getDatabase(1)),
                NodeDescription(devSeed: 2, database: getDatabase(2)),
                NodeDescription(devSeed: 3, database: .inMemory),
            ],
            connections: [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3)]
        ).build(genesis: .preset(.minimal))

        let (validator1, validator1StoreMiddlware) = nodes[0]
        let (validator2, validator2StoreMiddlware) = nodes[1]
        let (node1, node1StoreMiddlware) = nodes[2]
        let (node2, node2StoreMiddlware) = nodes[3]

        try await Task.sleep(for: .milliseconds(nodes.count * 500))

        // Verify connections
        #expect(node1.network.peersCount == 2)
        #expect(node2.network.peersCount == 2)

        // Advance time and verify sync
        for _ in 0 ..< 10 {
            await scheduler.advance(by: TimeInterval(validator1.blockchain.config.value.slotPeriodSeconds))
            await validator1StoreMiddlware.wait()
            await validator2StoreMiddlware.wait()
            await node1StoreMiddlware.wait()
            await node2StoreMiddlware.wait()
        }

        try await Task.sleep(for: .milliseconds(nodes.count * 500))

        let validator1BestHead = await validator1.dataProvider.bestHead
        let validator2BestHead = await validator2.dataProvider.bestHead
        let node1BestHead = await node1.dataProvider.bestHead
        let node2BestHead = await node2.dataProvider.bestHead
        #expect(validator1BestHead.hash == node1BestHead.hash)
        #expect(validator1BestHead.hash == node2BestHead.hash)
        #expect(validator2BestHead.hash == node1BestHead.hash)
    }
    
    @Test
    func moreMultiplePeers() async throws {
        // Create multiple nodes
        var nodeDescriptions: [NodeDescription] = [
            NodeDescription(isValidator: true, database: getDatabase(0)),
            NodeDescription(isValidator: true, devSeed: 1, database: getDatabase(1))
        ]
        
        // Add 18 non-validator nodes
        for i in 2...19 {
            nodeDescriptions.append(NodeDescription(devSeed: UInt32(i), database: .inMemory))
        }
        
        let (nodes, scheduler) = try await Topology(
            nodes: nodeDescriptions,
            connections: (0..<20).flatMap { i in
                (i + 1..<20).map { j in (i, j) } // Fully connected topology
            }
        ).build(genesis: .preset(.minimal))

        let (validator1, validator1StoreMiddlware) = nodes[0]
        let (validator2, validator2StoreMiddlware) = nodes[1]

        // Extract non-validator nodes and their middleware
        let nonValidatorNodes = nodes[2...].map { $0 }

        try await Task.sleep(for: .milliseconds(nodes.count * 200))
        let (node1, node1StoreMiddlware) = nonValidatorNodes[0]
        let (node2, node2StoreMiddlware) = nonValidatorNodes[1]
        // Verify connections for a sample of non-validator nodes
        #expect(node1.network.peersCount == 19)
        #expect(node2.network.peersCount == 19)
        // Advance time and verify sync
        for _ in 0 ..< 10 {
            await scheduler.advance(by: TimeInterval(validator1.blockchain.config.value.slotPeriodSeconds))
            await validator1StoreMiddlware.wait()
            await validator2StoreMiddlware.wait()
            
            for (_, middleware) in nonValidatorNodes {
                await middleware.wait()
            }
        }

        try await Task.sleep(for: .milliseconds(nodes.count * 200))

        let validator1BestHead = await validator1.dataProvider.bestHead
        let validator2BestHead = await validator2.dataProvider.bestHead
        
        for (node, _) in nonValidatorNodes {
            let nodeBestHead = await node.dataProvider.bestHead
            #expect(validator1BestHead.hash == nodeBestHead.hash)
            #expect(validator2BestHead.hash == nodeBestHead.hash)
        }
    }

    
}
