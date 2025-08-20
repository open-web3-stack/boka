import Blockchain
import Foundation
import JAMTests
import TracingUtils
import Utils

private let logger = Logger(label: "FuzzGeneratorTraces")

/// A fuzz generator that loads test cases from JAM conformance fuzz traces
public class FuzzGeneratorTraces: FuzzGenerator {
    private let testCases: [JamTestnetTestcase]
    private var currentIndex: Int = 0

    public init(tracesDir: String) throws {
        logger.info("Loading test vectors from directory: \(tracesDir)")

        testCases = try Self.loadTestCases(from: tracesDir)

        logger.info("Loaded \(testCases.count) test cases")

        if testCases.isEmpty {
            throw FuzzGeneratorError.invalidTestData("No test cases found in directory: \(tracesDir)")
        }
    }

    public func generateState(timeslot _: TimeslotIndex, config _: ProtocolConfigRef) async throws -> [FuzzKeyValue] {
        guard currentIndex < testCases.count else {
            throw FuzzGeneratorError.stateGenerationFailed("No more test cases available")
        }

        let testCase = testCases[currentIndex]

        logger.debug("Generating state for test case \(currentIndex + 1)/\(testCases.count)")

        let preStateDict = testCase.preState.toDict()
        let keyValues = preStateDict.map { key, value in
            FuzzKeyValue(key: key, value: value)
        }

        return keyValues
    }

    public func generateBlock(timeslot _: UInt32, currentStateRef _: StateRef, config _: ProtocolConfigRef) async throws -> BlockRef {
        guard currentIndex < testCases.count else {
            throw FuzzGeneratorError.blockGenerationFailed("No more test cases available")
        }

        let testCase = testCases[currentIndex]

        logger.debug("Generating block for test case \(currentIndex + 1)/\(testCases.count)")

        let block = testCase.block

        currentIndex += 1

        return block.asRef()
    }

    private static func loadTestCases(from directory: String) throws -> [JamTestnetTestcase] {
        logger.info("Loading test cases from directory: \(directory)")

        let basePath = directory

        guard FileManager.default.fileExists(atPath: basePath) else {
            throw FuzzGeneratorError.invalidTestData("Directory does not exist: \(basePath)")
        }

        let timestampDirs = try FileManager.default.contentsOfDirectory(atPath: basePath)
            .sorted()
            .filter { !$0.starts(with: ".") }

        var allDecodedTestCases: [JamTestnetTestcase] = []

        for timestamp in timestampDirs {
            let timestampPath = "\(basePath)/\(timestamp)"

            guard FileManager.default.fileExists(atPath: timestampPath) else {
                logger.warning("Timestamp directory does not exist: \(timestampPath)")
                continue
            }

            let testFiles = try FileManager.default.contentsOfDirectory(atPath: timestampPath)
                .filter { $0.hasSuffix(".bin") }
                .sorted()

            for testFile in testFiles {
                let testFilePath = "\(timestampPath)/\(testFile)"

                do {
                    let testData = try Data(contentsOf: URL(fileURLWithPath: testFilePath))
                    let rawTestCase = Testcase(description: testFile, data: testData)

                    let decoded = try JamTestnet.decodeTestcase(rawTestCase)
                    allDecodedTestCases.append(decoded)
                    logger.debug("Successfully loaded test case: \(timestamp)/\(testFile)")
                } catch {
                    logger.warning("Failed to decode test case \(timestamp)/\(testFile): \(error)")
                }
            }
        }

        logger.info("Successfully loaded \(allDecodedTestCases.count) test cases")
        return allDecodedTestCases
    }
}
