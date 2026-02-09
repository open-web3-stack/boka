import Blockchain
import Foundation
import JAMTests
import TracingUtils
import Utils

private let logger = Logger(label: "FuzzGeneratorTraces")

/// A fuzz generator that loads test cases from JAM conformance fuzz traces
public class FuzzGeneratorTraces: FuzzGenerator {
    private let testCases: [JamTestnetTestcase]

    public init(tracesDir: String) throws {
        logger.info("Loading test vectors from directory: \(tracesDir)")

        testCases = try Self.loadTestCases(from: tracesDir)

        logger.info("Loaded \(testCases.count) test cases")

        if testCases.isEmpty {
            throw FuzzGeneratorError.invalidTestData("No test cases found in directory: \(tracesDir)")
        }
    }

    public func generatePreState(
        timeslot: TimeslotIndex,
        config _: ProtocolConfigRef,
    ) async throws -> (stateRoot: Data32, keyValues: [FuzzKeyValue]) {
        let testIndex = Int(timeslot)
        guard testIndex >= 0, testIndex < testCases.count else {
            throw FuzzGeneratorError.stateGenerationFailed("No test case available for timeslot \(timeslot) (index \(testIndex))")
        }

        let testCase = testCases[testIndex]

        logger.debug("Generating pre-state for timeslot \(timeslot) (test case \(testIndex + 1)/\(testCases.count))")

        let keyValues = testCase.preState.keyvals.map { keyval in
            FuzzKeyValue(key: keyval.key, value: keyval.value)
        }

        return (stateRoot: testCase.preState.root, keyValues: keyValues)
    }

    public func generatePostState(
        timeslot: TimeslotIndex,
        config _: ProtocolConfigRef,
    ) async throws -> (stateRoot: Data32, keyValues: [FuzzKeyValue]) {
        let testIndex = Int(timeslot)
        guard testIndex >= 0, testIndex < testCases.count else {
            throw FuzzGeneratorError.stateGenerationFailed("No test case available for timeslot \(timeslot) (index \(testIndex))")
        }

        let testCase = testCases[testIndex]

        logger.debug("Generating expected post-state for timeslot \(timeslot) (test case \(testIndex + 1)/\(testCases.count))")

        let keyValues = testCase.postState.keyvals.map { keyval in
            FuzzKeyValue(key: keyval.key, value: keyval.value)
        }

        return (stateRoot: testCase.postState.root, keyValues: keyValues)
    }

    public func generateBlock(timeslot: UInt32, currentStateRef _: StateRef, config _: ProtocolConfigRef) async throws -> BlockRef {
        let testIndex = Int(timeslot)
        guard testIndex >= 0, testIndex < testCases.count else {
            throw FuzzGeneratorError.blockGenerationFailed("No test case available for timeslot \(timeslot) (index \(testIndex))")
        }

        let testCase = testCases[testIndex]

        logger.debug("Generating block for timeslot \(timeslot) (test case \(testIndex + 1)/\(testCases.count))")

        let block = testCase.block

        return block.asRef()
    }

    private static func loadTestCases(from directory: String) throws -> [JamTestnetTestcase] {
        logger.info("Loading test cases from directory: \(directory)")

        let basePath = directory

        guard FileManager.default.fileExists(atPath: basePath) else {
            throw FuzzGeneratorError.invalidTestData("Directory does not exist: \(basePath)")
        }

        var allDecodedTestCases: [JamTestnetTestcase] = []

        // Find all .bin files with depth of 2
        func findBinFiles(in path: String, currentDepth: Int = 0) throws -> [String] {
            guard currentDepth <= 2 else { return [] }

            var binFiles: [String] = []
            let contents = try FileManager.default.contentsOfDirectory(atPath: path)

            for item in contents {
                guard !item.starts(with: ".") else { continue }

                let itemPath = "\(path)/\(item)"
                var isDirectory: ObjCBool = false

                guard FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory) else {
                    continue
                }

                if isDirectory.boolValue, currentDepth < 2 {
                    // Recurse into subdirectory
                    binFiles += try findBinFiles(in: itemPath, currentDepth: currentDepth + 1)
                } else if !isDirectory.boolValue, item.hasSuffix(".bin") {
                    // Found a .bin file
                    binFiles.append(itemPath)
                }
            }

            return binFiles.sorted()
        }

        let testFiles = try findBinFiles(in: basePath)

        for testFilePath in testFiles {
            do {
                let testData = try Data(contentsOf: URL(fileURLWithPath: testFilePath))
                let rawTestCase = Testcase(description: URL(fileURLWithPath: testFilePath).lastPathComponent, data: testData)

                let decoded = try JamTestnet.decodeTestcase(rawTestCase)
                allDecodedTestCases.append(decoded)
                logger.debug("Successfully loaded test case: \(testFilePath)")
            } catch {
                logger.warning("Failed to decode test case \(testFilePath): \(error)")
            }
        }

        logger.info("Successfully loaded \(allDecodedTestCases.count) test cases")
        return allDecodedTestCases
    }
}
