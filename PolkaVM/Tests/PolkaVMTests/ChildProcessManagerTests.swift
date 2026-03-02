import Foundation
@testable import PolkaVM
import Testing
import Utils
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

@Suite(.serialized)
struct ChildProcessManagerTests {
    @Test
    func spawnChildProcess() async throws {
        #if os(macOS) || os(Linux)
            let manager = ChildProcessManager(defaultTimeout: 5.0)
            let (handle, clientFD) = try await manager.spawnChildProcess(executablePath: "/usr/bin/true")

            #expect(handle.pid > 0)
            #expect(clientFD >= 0)

            #if canImport(Glibc)
                _ = Glibc.close(clientFD)
            #elseif canImport(Darwin)
                _ = Darwin.close(clientFD)
            #endif

            _ = try await manager.waitForExit(handle: handle, timeout: 5.0)
        #else
            #expect(true)
        #endif
    }

    @Test
    func shortLivedFailingChildPreservesExitCode() async throws {
        #if os(macOS) || os(Linux)
            let manager = ChildProcessManager(defaultTimeout: 5.0)
            let (handle, clientFD) = try await manager.spawnChildProcess(executablePath: "/usr/bin/false")

            #if canImport(Glibc)
                _ = Glibc.close(clientFD)
            #elseif canImport(Darwin)
                _ = Darwin.close(clientFD)
            #endif

            let exitCode = try await manager.waitForExit(handle: handle, timeout: 5.0)
            #expect(exitCode != 0)
        #else
            #expect(true)
        #endif
    }

    @Test
    func invokePVMSandboxPathRespected() async {
        #if os(macOS) || os(Linux)
            let key = "BOKA_SANDBOX_PATH"
            let originalPath = getenv(key).map { String(cString: $0) }

            defer {
                if let originalPath {
                    _ = setenv(key, originalPath, 1)
                } else {
                    _ = unsetenv(key)
                }
            }

            _ = setenv(key, "/definitely/missing/boka-sandbox", 1)

            let sumToN = Data([
                0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
                51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
                61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
                36, 24,
            ])

            let (exitReason, _, _) = await invokePVM(
                config: DefaultPvmConfig(),
                executionMode: .sandboxed,
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([4]),
                ctx: nil,
            )

            #expect(exitReason == ExitReason.panic(.trap))
        #else
            #expect(true)
        #endif
    }

    @Test
    func invokePVMSandboxExecution() async {
        #if os(macOS) || os(Linux)
            let key = "BOKA_SANDBOX_PATH"
            let originalPath = getenv(key).map { String(cString: $0) }

            defer {
                if let originalPath {
                    _ = setenv(key, originalPath, 1)
                } else {
                    _ = unsetenv(key)
                }
            }

            guard let sandboxPath = resolveSandboxExecutablePathForTests() else {
                Issue.record("Unable to resolve sandbox executable. Set BOKA_SANDBOX_PATH for tests.")
                return
            }

            _ = setenv(key, sandboxPath, 1)

            let sumToN = Data([
                0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
                51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
                61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
                36, 24,
            ])

            let (exitReason, _, output) = await invokePVM(
                config: DefaultPvmConfig(),
                executionMode: .sandboxed,
                blob: sumToN,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([4]),
                ctx: nil,
            )

            #expect(exitReason == .halt)

            let outputValue = output?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0
            #expect(outputValue == 10)
        #else
            #expect(true)
        #endif
    }

    @Test
    func waitForExitTimeoutWithSIGKILLFallback() async throws {
        #if os(macOS) || os(Linux)
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent("child-process-timeout-\(UUID().uuidString)")
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? fileManager.removeItem(at: tempDir)
            }

            let scriptURL = tempDir.appendingPathComponent("ignore-term.sh")
            let scriptContents = """
            #!/bin/sh
            trap '' TERM
            while true; do
              sleep 1
            done
            """
            try scriptContents.write(to: scriptURL, atomically: true, encoding: .utf8)

            #if canImport(Glibc)
                _ = Glibc.chmod(scriptURL.path, 0o755)
            #elseif canImport(Darwin)
                _ = Darwin.chmod(scriptURL.path, 0o755)
            #endif

            let manager = ChildProcessManager(defaultTimeout: 5.0)
            let (handle, clientFD) = try await manager.spawnChildProcess(executablePath: scriptURL.path)
            defer {
                #if canImport(Glibc)
                    _ = Glibc.close(clientFD)
                #elseif canImport(Darwin)
                    _ = Darwin.close(clientFD)
                #endif
            }

            let start = Date()
            var sawTimeout = false

            do {
                _ = try await manager.waitForExit(handle: handle, timeout: 0.3)
                Issue.record("Expected timeout, but waitForExit returned normally")
            } catch let error as IPCError {
                if case .timeout = error {
                    sawTimeout = true
                } else {
                    Issue.record("Expected IPCError.timeout, got \(error)")
                }
            } catch {
                Issue.record("Expected IPCError.timeout, got \(error)")
            }

            let elapsed = Date().timeIntervalSince(start)
            #expect(sawTimeout)
            #expect(elapsed < 12.0)
        #else
            #expect(true)
        #endif
    }
}

private func resolveSandboxExecutablePathForTests() -> String? {
    let fileManager = FileManager.default
    let key = "BOKA_SANDBOX_PATH"
    if let explicitPath = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !explicitPath.isEmpty
    {
        return SandboxExecutableResolver.isExecutableAvailable(at: explicitPath) ? explicitPath : nil
    }

    if let testExecutablePath = CommandLine.arguments.first, !testExecutablePath.isEmpty {
        let siblingSandboxPath = URL(fileURLWithPath: testExecutablePath)
            .deletingLastPathComponent()
            .appendingPathComponent("boka-sandbox")
            .path
        if fileManager.isExecutableFile(atPath: siblingSandboxPath) {
            return siblingSandboxPath
        }
    }

    let resolution = SandboxExecutableResolver.resolve()
    guard SandboxExecutableResolver.isExecutableAvailable(at: resolution.path) else {
        return nil
    }

    return resolution.path
}
