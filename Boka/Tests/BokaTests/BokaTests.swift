import ArgumentParser
import Blockchain
@testable import Boka
import Foundation
import Logging
import Node
import Testing

struct BokaTests {
    @Test func commandWithInvalidPaths() async throws {
        let invalidChainPath = "/path/to/wrong/file.json"

        var boka = try #require(Boka.parseAsRoot([
            "--chain", invalidChainPath,
        ]) as? Boka)

        await #expect(throws: Error.self) {
            try await boka.run()
        }
    }

    @Test func rootCommandParsesArgumentAdapters() throws {
        let command = try #require(Boka.parseAsRoot([
            "--chain", "dev",
            "--rpc", "no",
            "--p2p", "127.0.0.1:1234",
            "--peers", "127.0.0.1:2345",
            "--validator",
            "--operator-rpc", "127.0.0.1:3456",
            "--dev-seed", "7",
            "--name", "coverage-node",
            "--local",
        ]) as? Boka)

        switch command.chain {
        case .preset(.dev):
            break
        default:
            Issue.record("Expected dev preset chain")
        }

        switch command.rpc {
        case .disabled:
            break
        default:
            Issue.record("Expected RPC to be disabled")
        }

        let (_, p2pPort) = command.p2p.getAddressAndPort()
        #expect(Int(p2pPort) == 1234)

        let peer = try #require(command.peers.first)
        let (_, peerPort) = peer.getAddressAndPort()
        #expect(Int(peerPort) == 2345)

        let operatorRpc = try #require(command.operatorRpc)
        let (_, operatorPort) = operatorRpc.getAddressAndPort()
        #expect(Int(operatorPort) == 3456)

        #expect(command.validator)
        #expect(command.devSeed == 7)
        #expect(command.name == "coverage-node")
        #expect(command.local)
    }

    @Test func maybeEnabledArgumentCoversEnabledDisabledAndInvalidValues() throws {
        let enabled = try #require(MaybeEnabled<TestArgument>(argument: "value"))
        switch enabled {
        case let .enabled(value):
            #expect(value.rawValue == "value")
        case .disabled:
            Issue.record("Expected enabled argument")
        }
        #expect(enabled.asOptional == TestArgument(rawValue: "value"))

        let disabled = try #require(MaybeEnabled<TestArgument>(argument: "NO"))
        switch disabled {
        case .enabled:
            Issue.record("Expected disabled argument")
        case .disabled:
            break
        }
        #expect(disabled.asOptional == nil)

        #expect(MaybeEnabled<TestArgument>(argument: "invalid") == nil)
    }

    @Test func fuzzSubcommandsParseDefaultsAndOptions() throws {
        let defaultTarget = try #require(Boka.parseAsRoot([
            "fuzz", "target",
        ]) as? Boka.Fuzz.Target)
        #expect(defaultTarget.socketPath == "/tmp/jam_conformance.sock")
        #expect(defaultTarget.config == .tiny)

        let target = try #require(Boka.parseAsRoot([
            "fuzz", "target",
            "--socket-path", "/tmp/custom-target.sock",
            "--config", "full",
        ]) as? Boka.Fuzz.Target)
        #expect(target.socketPath == "/tmp/custom-target.sock")
        #expect(target.config == .full)

        let fuzzer = try #require(Boka.parseAsRoot([
            "fuzz", "fuzzer",
            "--socket-path", "/tmp/custom-fuzzer.sock",
            "--config", "full",
            "--seed", "42",
            "--blocks", "3",
            "--traces-dir", "/tmp/traces",
        ]) as? Boka.Fuzz.Fuzzer)
        #expect(fuzzer.socketPath == "/tmp/custom-fuzzer.sock")
        #expect(fuzzer.config == .full)
        #expect(fuzzer.seed == 42)
        #expect(fuzzer.blocks == 3)
        #expect(fuzzer.tracesDir == "/tmp/traces")
    }

    @Test func generateWritesPresetChainspecWithCustomID() async throws {
        let root = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let output = root.appendingPathComponent("chainspec.json").path
        let command = try #require(Generate.parseAsRoot([
            "--config", "tiny",
            "--id", "coverage-chain",
            output,
        ]) as? Generate)

        try await command.run()

        let generated = try await Genesis.file(path: output).load()
        #expect(generated.id == "coverage-chain")
    }

    @Test func fuzzEnvironmentIsIgnoredWhenDisabled() throws {
        let launch = try FuzzEnvironmentLaunch.parse(environment: [:])
        #expect(launch == nil)
    }

    @Test func fuzzEnvironmentParsesRequiredValues() throws {
        let launch = try #require(try FuzzEnvironmentLaunch.parse(environment: [
            "JAM_FUZZ": "",
            "JAM_FUZZ_SPEC": "tiny",
            "JAM_FUZZ_DATA_PATH": "/tmp/boka-fuzz-data",
            "JAM_FUZZ_SOCK_PATH": "/tmp/boka-fuzz.sock",
            "JAM_FUZZ_LOG_LEVEL": "warn",
        ]))

        #expect(launch.spec == .tiny)
        #expect(launch.dataPath == "/tmp/boka-fuzz-data")
        #expect(launch.socketPath == "/tmp/boka-fuzz.sock")
        #expect(launch.logLevel == Logger.Level.warning)
    }

    @Test func fuzzEnvironmentParsesFullSpecTrimmedValuesAndLogLevels() throws {
        let cases: [(String?, Logger.Level)] = [
            (nil, .info),
            ("", .info),
            (" error ", .error),
            ("WARN", .warning),
            ("info", .info),
            ("debug", .debug),
            ("trace", .trace),
        ]

        for (logLevel, expectedLevel) in cases {
            let launch = try #require(try FuzzEnvironmentLaunch.parse(environment: fuzzEnvironment(
                spec: " full ",
                dataPath: " /tmp/boka-fuzz-data ",
                socketPath: " /tmp/boka-fuzz.sock ",
                logLevel: logLevel,
            )))

            #expect(launch.spec == .full)
            #expect(launch.dataPath == "/tmp/boka-fuzz-data")
            #expect(launch.socketPath == "/tmp/boka-fuzz.sock")
            #expect(launch.logLevel == expectedLevel)
        }
    }

    @Test func fuzzEnvironmentRejectsMissingRequiredValues() {
        expectFuzzEnvironmentError(
            .missingRequiredVariable("JAM_FUZZ_SPEC"),
            environment: ["JAM_FUZZ": "1"],
        )
    }

    @Test func fuzzEnvironmentRejectsEmptyRequiredValues() {
        expectFuzzEnvironmentError(
            .emptyRequiredVariable("JAM_FUZZ_DATA_PATH"),
            environment: fuzzEnvironment(dataPath: " \n "),
        )
    }

    @Test func fuzzEnvironmentRejectsInvalidSpecAndLogLevel() {
        expectFuzzEnvironmentError(
            .invalidSpec("dev"),
            environment: fuzzEnvironment(spec: "dev", logLevel: nil),
        )

        expectFuzzEnvironmentError(
            .invalidLogLevel("notice"),
            environment: fuzzEnvironment(logLevel: "notice"),
        )
    }

    @Test func fuzzEnvironmentErrorsHaveStableDescriptions() {
        let cases: [(FuzzEnvironmentLaunch.Error, String)] = [
            (
                .missingRequiredVariable("JAM_FUZZ_SPEC"),
                "JAM_FUZZ_SPEC is required when JAM_FUZZ is defined",
            ),
            (
                .emptyRequiredVariable("JAM_FUZZ_DATA_PATH"),
                "JAM_FUZZ_DATA_PATH must not be empty when JAM_FUZZ is defined",
            ),
            (
                .invalidSpec("dev"),
                "JAM_FUZZ_SPEC must be 'tiny' or 'full', got 'dev'",
            ),
            (
                .invalidLogLevel("notice"),
                "JAM_FUZZ_LOG_LEVEL must be one of error, warn, info, debug, trace, got 'notice'",
            ),
            (
                .pathIsNotDirectory(variable: "JAM_FUZZ_DATA_PATH", path: "/tmp/file"),
                "JAM_FUZZ_DATA_PATH must be a directory, got '/tmp/file'",
            ),
            (
                .pathIsNotWritable(variable: "JAM_FUZZ_DATA_PATH", path: "/tmp/readonly"),
                "JAM_FUZZ_DATA_PATH must be writable, got '/tmp/readonly'",
            ),
        ]

        for (error, description) in cases {
            #expect(error.description == description)
            #expect(error.errorDescription == description)
        }
    }

    @Test func fuzzEnvironmentPreparesDataAndSocketDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let dataPath = root.appendingPathComponent("data", isDirectory: true).path
        let socketPath = root.appendingPathComponent("socket/fuzz.sock").path
        let launch = FuzzEnvironmentLaunch(
            socketPath: socketPath,
            spec: .tiny,
            dataPath: dataPath,
            logLevel: .info,
        )

        try launch.prepareFilesystem()

        var isDirectory = ObjCBool(false)
        #expect(FileManager.default.fileExists(atPath: dataPath, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        isDirectory = ObjCBool(false)
        let socketDirectory = (socketPath as NSString).deletingLastPathComponent
        #expect(FileManager.default.fileExists(atPath: socketDirectory, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func fuzzEnvironmentAcceptsSocketPathInCurrentDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let dataPath = root.appendingPathComponent("data", isDirectory: true).path
        let launch = FuzzEnvironmentLaunch(
            socketPath: "fuzz.sock",
            spec: .tiny,
            dataPath: dataPath,
            logLevel: .info,
        )

        try launch.prepareFilesystem()

        var isDirectory = ObjCBool(false)
        #expect(FileManager.default.fileExists(atPath: dataPath, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func fuzzEnvironmentRejectsFileWhereDirectoryIsRequired() throws {
        let root = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let filePath = root.appendingPathComponent("not-a-directory").path
        #expect(FileManager.default.createFile(atPath: filePath, contents: Data()))

        let launch = FuzzEnvironmentLaunch(
            socketPath: root.appendingPathComponent("fuzz.sock").path,
            spec: .tiny,
            dataPath: filePath,
            logLevel: .info,
        )

        do {
            try launch.prepareFilesystem()
            Issue.record("Expected file data path to be rejected")
        } catch let error as FuzzEnvironmentLaunch.Error {
            #expect(error == .pathIsNotDirectory(variable: "JAM_FUZZ_DATA_PATH", path: filePath))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func fuzzEnvironmentRejectsUnwritableDataDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let dataPath = root.appendingPathComponent("readonly", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: dataPath, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dataPath)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dataPath)
        }

        let launch = FuzzEnvironmentLaunch(
            socketPath: root.appendingPathComponent("fuzz.sock").path,
            spec: .tiny,
            dataPath: dataPath,
            logLevel: .info,
        )

        do {
            try launch.prepareFilesystem()
            Issue.record("Expected unwritable data path to be rejected")
        } catch let error as FuzzEnvironmentLaunch.Error {
            #expect(error == .pathIsNotWritable(variable: "JAM_FUZZ_DATA_PATH", path: dataPath))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func expectFuzzEnvironmentError(
        _ expected: FuzzEnvironmentLaunch.Error,
        environment: [String: String],
    ) {
        do {
            _ = try FuzzEnvironmentLaunch.parse(environment: environment)
            Issue.record("Expected error: \(expected.description)")
        } catch let error as FuzzEnvironmentLaunch.Error {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func fuzzEnvironment(
        spec: String = "tiny",
        dataPath: String = "/tmp/boka-fuzz-data",
        socketPath: String = "/tmp/boka-fuzz.sock",
        logLevel: String? = "warn",
    ) -> [String: String] {
        var environment = [
            "JAM_FUZZ": "1",
            "JAM_FUZZ_SPEC": spec,
            "JAM_FUZZ_DATA_PATH": dataPath,
            "JAM_FUZZ_SOCK_PATH": socketPath,
        ]

        if let logLevel {
            environment["JAM_FUZZ_LOG_LEVEL"] = logLevel
        }

        return environment
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("boka-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private struct TestArgument: ExpressibleByArgument, Equatable {
    let rawValue: String

    init?(argument: String) {
        guard argument != "invalid" else {
            return nil
        }
        rawValue = argument
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}
