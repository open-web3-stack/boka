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

    @Test func fuzzEnvironmentRejectsMissingRequiredValues() throws {
        do {
            _ = try FuzzEnvironmentLaunch.parse(environment: ["JAM_FUZZ": "1"])
            Issue.record("Expected missing JAM_FUZZ_SPEC to fail")
        } catch FuzzEnvironmentLaunch.Error.missingRequiredVariable("JAM_FUZZ_SPEC") {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func fuzzEnvironmentRejectsInvalidSpecAndLogLevel() throws {
        do {
            _ = try FuzzEnvironmentLaunch.parse(environment: [
                "JAM_FUZZ": "1",
                "JAM_FUZZ_SPEC": "dev",
                "JAM_FUZZ_DATA_PATH": "/tmp/boka-fuzz-data",
                "JAM_FUZZ_SOCK_PATH": "/tmp/boka-fuzz.sock",
            ])
            Issue.record("Expected invalid JAM_FUZZ_SPEC to fail")
        } catch FuzzEnvironmentLaunch.Error.invalidSpec("dev") {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try FuzzEnvironmentLaunch.parse(environment: [
                "JAM_FUZZ": "1",
                "JAM_FUZZ_SPEC": "tiny",
                "JAM_FUZZ_DATA_PATH": "/tmp/boka-fuzz-data",
                "JAM_FUZZ_SOCK_PATH": "/tmp/boka-fuzz.sock",
                "JAM_FUZZ_LOG_LEVEL": "notice",
            ])
            Issue.record("Expected invalid JAM_FUZZ_LOG_LEVEL to fail")
        } catch FuzzEnvironmentLaunch.Error.invalidLogLevel("notice") {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func fuzzEnvironmentPreparesDataAndSocketDirectories() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("boka-fuzz-env-\(UUID().uuidString)", isDirectory: true)
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
}
