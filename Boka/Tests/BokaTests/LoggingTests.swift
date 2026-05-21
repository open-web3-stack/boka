@testable import Boka
import ConsoleKit
import Logging
import Testing

struct LoggingTests {
    @Test func parseLevelAcceptsSupportedNames() {
        let cases: [(String, Logger.Level)] = [
            ("trace", .trace),
            ("DEBUG", .debug),
            (" info ", .info),
            ("notice", .notice),
            ("warn", .warning),
            ("warning", .warning),
            ("error", .error),
            ("critical", .critical),
        ]

        for (value, expected) in cases {
            #expect(parseLevel(value) == expected)
        }

        #expect(parseLevel("verbose") == nil)
    }

    @Test func parseLogLevelConfigurationDefaultsAndFilters() throws {
        let defaultOnly = try #require(parse(from: "debug"))
        #expect(defaultOnly.filters.isEmpty)
        #expect(defaultOnly.defaultLevel == .debug)
        #expect(defaultOnly.minimalLevel == .debug)

        let filtered = try #require(parse(from: "node=trace,rpc=error,warning"))
        #expect(filtered.filters["node"] == .trace)
        #expect(filtered.filters["rpc"] == .error)
        #expect(filtered.defaultLevel == .warning)
        #expect(filtered.minimalLevel == .trace)

        let filtersOnly = try #require(parse(from: "node=warn,rpc=error"))
        #expect(filtersOnly.filters["node"] == .warning)
        #expect(filtersOnly.filters["rpc"] == .error)
        #expect(filtersOnly.defaultLevel == .info)
        #expect(filtersOnly.minimalLevel == .info)
    }

    @Test func parseLogLevelConfigurationRejectsInvalidValues() {
        #expect(parse(from: "verbose") == nil)
        #expect(parse(from: "node=verbose") == nil)
        #expect(parse(from: "node=debug=extra") == nil)
    }

    @Test func bokaLoggerResolvesExactPrefixAndDefaultLevels() {
        let logger = BokaLogger(
            fragment: EmptyLogFragment(),
            label: "cli",
            metadataProvider: nil,
            defaultLevel: .warning,
            filters: ["node": .debug],
        )

        #expect(logger.levelFor(label: "node") == .debug)
        #expect(logger.levelFor(label: "NODE.sync") == .debug)
        #expect(logger.levelFor(label: "rpc") == .warning)
        #expect(logger.levelFor(label: "RPC") == .warning)
    }

    @Test func bokaLoggerStoresMetadataAndHonorsFilterThreshold() {
        var logger = BokaLogger(
            fragment: EmptyLogFragment(),
            label: "cli",
            metadataProvider: nil,
            defaultLevel: .error,
        )

        logger[metadataKey: "role"] = "validator"
        #expect(logger[metadataKey: "role"] == "validator")

        logger.log(
            level: .debug,
            message: "filtered",
            metadata: nil,
            source: "test",
            file: #filePath,
            function: #function,
            line: #line,
        )

        logger.log(
            level: .critical,
            message: "emitted",
            metadata: ["request": "1"],
            source: "test",
            file: #filePath,
            function: #function,
            line: #line,
        )
    }
}

private struct EmptyLogFragment: LoggerFragment {
    func write(_: inout LogRecord, to _: inout FragmentOutput) {}
}
