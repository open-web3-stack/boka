import Foundation
import Fuzzing
import Logging

struct FuzzEnvironmentLaunch {
    enum Error: Swift.Error, Equatable, CustomStringConvertible, LocalizedError {
        case missingRequiredVariable(String)
        case emptyRequiredVariable(String)
        case invalidSpec(String)
        case invalidLogLevel(String)
        case pathIsNotDirectory(variable: String, path: String)
        case pathIsNotWritable(variable: String, path: String)

        var description: String {
            switch self {
            case let .missingRequiredVariable(variable):
                "\(variable) is required when JAM_FUZZ is defined"
            case let .emptyRequiredVariable(variable):
                "\(variable) must not be empty when JAM_FUZZ is defined"
            case let .invalidSpec(value):
                "JAM_FUZZ_SPEC must be 'tiny' or 'full', got '\(value)'"
            case let .invalidLogLevel(value):
                "JAM_FUZZ_LOG_LEVEL must be one of error, warn, info, debug, trace, got '\(value)'"
            case let .pathIsNotDirectory(variable, path):
                "\(variable) must be a directory, got '\(path)'"
            case let .pathIsNotWritable(variable, path):
                "\(variable) must be writable, got '\(path)'"
            }
        }

        var errorDescription: String? {
            description
        }
    }

    let socketPath: String
    let spec: Boka.Fuzz.JamConfig
    let dataPath: String
    let logLevel: Logger.Level

    static func parse(environment: [String: String]) throws -> FuzzEnvironmentLaunch? {
        guard environment.keys.contains("JAM_FUZZ") else { return nil }

        let specValue = try requiredValue("JAM_FUZZ_SPEC", in: environment)
        let spec = switch specValue {
        case "tiny":
            Boka.Fuzz.JamConfig.tiny
        case "full":
            Boka.Fuzz.JamConfig.full
        default:
            throw Error.invalidSpec(specValue)
        }

        return FuzzEnvironmentLaunch(
            socketPath: try requiredValue("JAM_FUZZ_SOCK_PATH", in: environment),
            spec: spec,
            dataPath: try requiredValue("JAM_FUZZ_DATA_PATH", in: environment),
            logLevel: try parseLogLevel(environment["JAM_FUZZ_LOG_LEVEL"]),
        )
    }

    func run() async throws {
        try prepareFilesystem()

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = logLevel
            return handler
        }

        let fuzzTarget = try FuzzingTarget(socketPath: socketPath, config: spec.rawValue)
        try await fuzzTarget.run()
    }

    func prepareFilesystem() throws {
        try prepareDirectory(path: dataPath, variable: "JAM_FUZZ_DATA_PATH")

        let socketDirectory = socketParentDirectory(for: socketPath)
        try prepareDirectory(path: socketDirectory, variable: "JAM_FUZZ_SOCK_PATH")
    }

    private static func requiredValue(_ key: String, in environment: [String: String]) throws -> String {
        guard let value = environment[key] else {
            throw Error.missingRequiredVariable(key)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Error.emptyRequiredVariable(key)
        }
        return trimmed
    }

    private static func parseLogLevel(_ value: String?) throws -> Logger.Level {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .info
        }

        switch value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "error":
            return .error
        case "warn":
            return .warning
        case "info":
            return .info
        case "debug":
            return .debug
        case "trace":
            return .trace
        default:
            throw Error.invalidLogLevel(value)
        }
    }

    private func prepareDirectory(path: String, variable: String) throws {
        var isDirectory = ObjCBool(false)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw Error.pathIsNotDirectory(variable: variable, path: path)
            }
        } else {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
            )
        }

        guard fileManager.isWritableFile(atPath: path) else {
            throw Error.pathIsNotWritable(variable: variable, path: path)
        }
    }

    private func socketParentDirectory(for socketPath: String) -> String {
        let parent = (socketPath as NSString).deletingLastPathComponent
        return parent.isEmpty ? "." : parent
    }
}
