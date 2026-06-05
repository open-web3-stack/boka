import Benchmark
import Blockchain
import Foundation
import PolkaVM
import Utils

private enum StorageWriteBenchmarkError: Error {
    case invalidMemoryRead
}

private final class StorageWriteBenchmarkVMState: VMState {
    private static let keyAddress = UInt32(0x1_0000)
    private static let valueAddress = UInt32(0x2_0000)

    private let key: Data
    private let value: Data

    var program: ProgramCode {
        fatalError("StorageWriteBenchmarkVMState does not execute program code")
    }

    var pc: UInt32 { 0 }

    init(key: Data, value: Data) {
        self.key = key
        self.value = value
    }

    func getRegisters() -> Registers {
        var registers = Registers()
        registers[Registers.Index(raw: 7)] = UInt64(Self.keyAddress)
        registers[Registers.Index(raw: 8)] = UInt64(key.count)
        registers[Registers.Index(raw: 9)] = UInt64(Self.valueAddress)
        registers[Registers.Index(raw: 10)] = UInt64(value.count)
        return registers
    }

    func readRegister<T: FixedWidthInteger>(_ index: Registers.Index) -> T {
        return registerValue(raw: UInt8(index.value))
    }

    func readRegister<T: FixedWidthInteger>(_ index: Registers.Index, _ index2: Registers.Index) -> (T, T) {
        (readRegister(index), readRegister(index2))
    }

    func readRegisters<T: FixedWidthInteger>(in range: Range<UInt8>) -> [T] {
        range.map { registerValue(raw: $0) }
    }

    func writeRegister(_: Registers.Index, _: some FixedWidthInteger) {}

    func getMemory() -> ReadonlyMemory {
        fatalError("StorageWriteBenchmarkVMState does not expose full memory")
    }

    func getMemoryUnsafe() -> GeneralMemory {
        fatalError("StorageWriteBenchmarkVMState does not expose full memory")
    }

    func isMemoryReadable(address: some FixedWidthInteger, length: Int) -> Bool {
        memorySlice(address: UInt32(truncatingIfNeeded: address), length: length) != nil
    }

    func isMemoryWritable(address _: some FixedWidthInteger, length _: Int) -> Bool {
        false
    }

    func readMemory(address: some FixedWidthInteger) throws -> UInt8 {
        guard let byte = memorySlice(address: UInt32(truncatingIfNeeded: address), length: 1)?.first else {
            throw StorageWriteBenchmarkError.invalidMemoryRead
        }
        return byte
    }

    func readMemory(address: some FixedWidthInteger, length: Int) throws -> Data {
        guard let data = memorySlice(address: UInt32(truncatingIfNeeded: address), length: length) else {
            throw StorageWriteBenchmarkError.invalidMemoryRead
        }
        return data
    }

    func writeMemory(address _: some FixedWidthInteger, value _: UInt8) throws {
        fatalError("StorageWriteBenchmarkVMState is read-only")
    }

    func writeMemory(address _: some FixedWidthInteger, values _: some Sequence<UInt8>) throws {
        fatalError("StorageWriteBenchmarkVMState is read-only")
    }

    func writeMemory(address _: some FixedWidthInteger, values _: Data) throws {
        fatalError("StorageWriteBenchmarkVMState is read-only")
    }

    func sbrk(_: UInt32) throws -> UInt32 {
        fatalError("StorageWriteBenchmarkVMState does not allocate memory")
    }

    func getGas() -> GasInt {
        GasInt(0)
    }

    func consumeGas(_: Gas) {}

    func increasePC(_: UInt32) {}

    func updatePC(_: UInt32) {}

    func withExecutingInst<R>(_ block: () throws -> R) rethrows -> R {
        try block()
    }

    private func registerValue<T: FixedWidthInteger>(raw: UInt8) -> T {
        switch raw {
        case 7:
            T(truncatingIfNeeded: Self.keyAddress)
        case 8:
            T(truncatingIfNeeded: key.count)
        case 9:
            T(truncatingIfNeeded: Self.valueAddress)
        case 10:
            T(truncatingIfNeeded: value.count)
        default:
            T(0)
        }
    }

    private func memorySlice(address: UInt32, length: Int) -> Data? {
        guard length >= 0 else { return nil }
        if let data = memorySlice(in: key, baseAddress: Self.keyAddress, address: address, length: length) {
            return data
        }
        return memorySlice(in: value, baseAddress: Self.valueAddress, address: address, length: length)
    }

    private func memorySlice(in data: Data, baseAddress: UInt32, address: UInt32, length: Int) -> Data? {
        let endAddress = address &+ UInt32(length)
        guard address >= baseAddress, endAddress >= address, endAddress <= baseAddress + UInt32(data.count) else {
            return nil
        }
        let offset = Int(address - baseAddress)
        return Data(data[offset ..< offset + length])
    }
}

func stateBackendBenchmarks() {
    Benchmark.defaultConfiguration.timeUnits = BenchmarkTimeUnits.microseconds

    // MARK: - Setup helpers

    func createTestData(count: Int) -> [(key: Data31, value: Data)] {
        (0 ..< count).map { i in
            let data = Data([UInt8(i % 256), UInt8((i / 256) % 256), UInt8((i / 65536) % 256)])
            return (key: Data31(data.blake2b256hash().data[relative: 0 ..< 31])!, value: data + Data(repeating: UInt8(i % 256), count: 32))
        }
    }

    func createTestDataWithSharedPrefix(count: Int, prefix: UInt8 = 0x00) -> [(key: Data31, value: Data)] {
        (0 ..< count).map { i in
            // Create keys with a shared prefix byte for prefix iteration benchmarking
            let keyData = Data([prefix] + [UInt8(i % 256), UInt8((i / 256) % 256)] + Data(repeating: 0, count: 28))
            let valueData = Data([UInt8(i % 256), UInt8((i / 256) % 256), UInt8((i / 65536) % 256)])
            return (key: Data31(keyData)!, value: valueData + Data(repeating: UInt8(i % 256), count: 32))
        }
    }

    func createTestDataWithSpreadPrefixes(count: Int) -> [(key: Data31, value: Data)] {
        (0 ..< count).map { i in
            let keyData = Data([UInt8(i % 256), UInt8((i / 256) % 256), UInt8((i / 65536) % 256)] + Data(repeating: 0, count: 28))
            let valueData = Data([UInt8(i % 256), UInt8((i / 256) % 256), UInt8((i / 65536) % 256)])
            return (key: Data31(keyData)!, value: valueData + Data(repeating: UInt8(i % 256), count: 32))
        }
    }

    func sortedByKey(_ values: [(key: Data31, value: Data)]) -> [(key: Data31, value: Data)] {
        values.sorted { $0.key.data.lexicographicallyPrecedes($1.key.data) }
    }

    func createStateLayerChanges(count: Int) -> [(key: any StateKey, value: Codable & Sendable)] {
        (0 ..< count).map { i in
            let keyData = Data([UInt8(i % 256), UInt8((i / 256) % 256)])
            let value = Data([UInt8(i % 256)]) + Data(repeating: UInt8((i / 256) % 256), count: 32)
            return (key: StateKeys.ServiceAccountStorageKey(index: ServiceIndex(i), key: keyData), value: value)
        }
    }

    func createServiceStorageWrites(count: Int) -> [(key: Data, oldValue: Data, newValue: Data)] {
        (0 ..< count).map { i in
            let key = Data([UInt8(i % 256), UInt8((i / 256) % 256), UInt8((i / 65536) % 256)])
            let oldValue = Data(repeating: UInt8(i % 251), count: 64)
            let newValue = Data(repeating: UInt8((i + 1) % 251), count: 96)
            return (key: key, oldValue: oldValue, newValue: newValue)
        }
    }

    func createServiceAccountsWithStorage(
        config: ProtocolConfigRef,
        serviceIndex: ServiceIndex,
        writes: [(key: Data, oldValue: Data, newValue: Data)]
    ) async throws -> ServiceAccountsMutRef {
        var state = State.dummy(config: config)
        var account = ServiceAccount.dummy(config: config).toDetails()
        account.balance = Balance(UInt64.max)
        state.set(serviceAccount: serviceIndex, account: account)
        for write in writes {
            try await state.set(serviceAccount: serviceIndex, storageKey: write.key, value: write.oldValue)
        }
        return ServiceAccountsMutRef(state)
    }

    // MARK: - State Layer Operations

    Benchmark("statelayer.fixedKeys.getset", configuration: BokaBenchmark.milliseconds) { benchmark in
        var state = State.dummy(config: ProtocolConfigRef.dev)
        var checksum: UInt64 = 0

        benchmark.startMeasurement()
        for i in 0 ..< 10000 {
            state.timeslot = TimeslotIndex(i)
            checksum &+= UInt64(state.timeslot)
        }
        benchmark.stopMeasurement()

        blackHole(checksum)
        blackHole(state)
    }

    Benchmark("statelayer.toKV.changedCount", configuration: BokaBenchmark.milliseconds) { benchmark in
        let layer = StateLayer(changes: createStateLayerChanges(count: 1000))
        var checksum = 0

        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            for item in layer.toKV() {
                checksum &+= item.key.data.count
                if item.value != nil {
                    checksum &+= 1
                }
            }
        }
        benchmark.stopMeasurement()

        blackHole(checksum)
    }

    Benchmark("serviceaccounts.storage.hostWrite.batch", configuration: BokaBenchmark.milliseconds) { benchmark in
        let config = ProtocolConfigRef.dev
        let serviceIndex = ServiceIndex(100)
        let writes = createServiceStorageWrites(count: 1000)
        let accounts = try await createServiceAccountsWithStorage(
            config: config,
            serviceIndex: serviceIndex,
            writes: writes,
        )
        let vmStates = writes.map { StorageWriteBenchmarkVMState(key: $0.key, value: $0.newValue) }
        let hostCall = Write(serviceIndex: serviceIndex, accounts: accounts)

        benchmark.startMeasurement()
        for vmState in vmStates {
            try await hostCall._callImpl(config: config, state: vmState)
        }
        benchmark.stopMeasurement()

        blackHole(accounts.changes)
    }

    // MARK: - Trie Node Operations

    Benchmark("statebackend.get.node.hit") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        // Get a node hash that exists
        let root = await trie.rootHash

        benchmark.startMeasurement()
        let result = try await backend.read(key: root.data.suffix(31))
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("statebackend.get.node.miss") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        let randomKey = Data31.random()

        benchmark.startMeasurement()
        let result = try await backend.read(key: randomKey.data)
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("statebackend.get.batch", configuration: BokaBenchmark.milliseconds) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)
        try await trie.update(testData)
        try await trie.save()

        // Collect node keys from trie
        let root = await trie.rootHash
        var nodeKeys: [Data] = []
        nodeKeys.append(root.data.suffix(31))

        benchmark.startMeasurement()
        var results: [Data?] = []
        for key in nodeKeys {
            let result = try await backend.read(key: key)
            results.append(result)
        }
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - Put Operations

    Benchmark("statebackend.put.node") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1)

        benchmark.startMeasurement()
        try await trie.update(testData)
        try await trie.save()
        benchmark.stopMeasurement()
    }

    Benchmark("statebackend.put.batch", configuration: BokaBenchmark.milliseconds) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 1000)

        benchmark.startMeasurement()
        try await trie.update(testData)
        try await trie.save()
        benchmark.stopMeasurement()
    }

    // MARK: - Cache Operations

    Benchmark("statebackend.cache.hit") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        // Read the same key multiple times (cache hits in trie's node cache)
        benchmark.startMeasurement()
        var results: [Data?] = []
        for _ in 0 ..< 100 {
            let result = try await trie.read(key: testData[50].key)
            results.append(result)
        }
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.cache.miss") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        benchmark.startMeasurement()
        // Read different keys each time (cache misses)
        var results: [Data?] = []
        for data in testData {
            let result = try await trie.read(key: data.key)
            results.append(result)
        }
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - Storage Query Operations

    Benchmark("statebackend.storage.query") { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestData(count: 100)
        try await trie.update(testData)
        try await trie.save()

        benchmark.startMeasurement()
        let result = try await trie.read(key: testData[50].key)
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("statebackend.storage.prefix", configuration: BokaBenchmark.milliseconds) { benchmark in
        let backend = InMemoryBackend()
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let testData = createTestDataWithSharedPrefix(count: 1000)
        try await trie.update(testData)
        try await trie.save()

        // Use prefix that matches all keys (first byte is 0x00 for all keys)
        let prefix = Data([0x00])

        benchmark.startMeasurement()
        let results = try await trie.getKeys(matchingPrefix: prefix, bitsCount: 8)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - State Backend Read/Write Operations

    Benchmark("statebackend.read.single") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1)
        try await stateBackend.writeRaw(testData)

        benchmark.startMeasurement()
        let result = try await stateBackend.readRaw(testData[0].key)
        benchmark.stopMeasurement()
        blackHole(result)
    }

    Benchmark("statebackend.write.single") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1)

        benchmark.startMeasurement()
        try await stateBackend.writeRaw(testData)
        benchmark.stopMeasurement()
    }

    Benchmark("statebackend.write.batch", configuration: BokaBenchmark.milliseconds) { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1000)

        benchmark.startMeasurement()
        try await stateBackend.writeRaw(testData)
        benchmark.stopMeasurement()
    }

    // MARK: - Get Keys with Prefix/StartKey/Limit

    Benchmark("statebackend.getkeys.prefix") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestDataWithSharedPrefix(count: 1000)
        try await stateBackend.writeRaw(testData)

        // Use prefix that matches all keys (first byte is 0x00)
        let prefix = Data([0x00])

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(prefix, nil, nil)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.getkeys.startkey") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1000)
        try await stateBackend.writeRaw(testData)

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(nil, testData[100].key, nil)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.getkeys.limit") { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestData(count: 1000)
        try await stateBackend.writeRaw(testData)

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(nil, nil, 100)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.getkeys.limit.smallFromLarge", configuration: BokaBenchmark.milliseconds) { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestDataWithSharedPrefix(count: 8192)
        try await stateBackend.writeRaw(testData)

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(Data([0x00]), nil, 10)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.getkeys.startkey.deep", configuration: BokaBenchmark.milliseconds) { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestDataWithSharedPrefix(count: 8192)
        try await stateBackend.writeRaw(testData)
        let sortedData = sortedByKey(testData)
        let startKey = sortedData[8000].key

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(Data([0x00]), startKey, 25)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.getkeys.prefix.sparse", configuration: BokaBenchmark.milliseconds) { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestDataWithSpreadPrefixes(count: 8192)
        try await stateBackend.writeRaw(testData)

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(Data([0x7F]), nil, nil)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    Benchmark("statebackend.getkeys.complex", configuration: BokaBenchmark.milliseconds) { benchmark in
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let testData = createTestDataWithSharedPrefix(count: 1000)
        try await stateBackend.writeRaw(testData)

        // Use prefix that matches all keys (first byte is 0x00)
        let prefix = Data([0x00])
        let startKey = testData[100].key
        let limit: UInt32 = 100

        benchmark.startMeasurement()
        let results = try await stateBackend.getKeys(prefix, startKey, limit)
        benchmark.stopMeasurement()
        blackHole(results)
    }

    // MARK: - Batch Update Operations

    Benchmark("statebackend.batchupdate.write") { benchmark in
        let backend = InMemoryBackend()
        let testData = createTestData(count: 100)
        let ops: [StateBackendOperation] = testData.map { .write(key: $0.key.data, value: $0.value) }

        benchmark.startMeasurement()
        try await backend.batchUpdate(ops)
        benchmark.stopMeasurement()
    }

    Benchmark("statebackend.batchupdate.mixed", configuration: BokaBenchmark.milliseconds) { benchmark in
        let backend = InMemoryBackend()
        let testData = createTestData(count: 1000)

        // Create mixed operations: writes, ref updates
        var ops: [StateBackendOperation] = []
        for data in testData {
            ops.append(.write(key: data.key.data, value: data.value))
            ops.append(.refUpdate(key: data.key.data, delta: 1))
        }

        benchmark.startMeasurement()
        try await backend.batchUpdate(ops)
        benchmark.stopMeasurement()
    }
}
