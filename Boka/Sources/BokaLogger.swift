import ConsoleKit
import Logging
import Utils

public struct BokaLogger<T: LoggerFragment>: LogHandler, Sendable {
    public let label: String
    public var metadata: Logger.Metadata
    public var metadataProvider: Logger.MetadataProvider?
    public var logLevel: Logger.Level
    public let console: Terminal
    public var fragment: T

    private let defaultLevel: Logger.Level
    private let filters: ThreadSafeContainer<[String: Logger.Level]>

    public init(
        fragment: T,
        label: String,
        level: Logger.Level = .debug,
        metadata: Logger.Metadata = [:],
        metadataProvider: Logger.MetadataProvider?,
        defaultLevel: Logger.Level = .info,
        filters: [String: Logger.Level] = [:]
    ) {
        self.fragment = fragment
        self.label = label
        self.metadata = metadata
        logLevel = level
        console = Terminal()
        self.metadataProvider = metadataProvider
        self.defaultLevel = defaultLevel
        self.filters = .init(filters)
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let labelLevel = levelFor(label: label)
        if labelLevel > level {
            return
        }

        var output = FragmentOutput()
        var record = LogRecord(
            level: level,
            message: message,
            metadata: metadata,
            source: source,
            file: file,
            function: function,
            line: line,
            label: label,
            loggerLevel: logLevel,
            loggerMetadata: self.metadata,
            metadataProvider: metadataProvider
        )

        fragment.write(&record, to: &output)

        console.output(output.text)
    }

    public func levelFor(label: String) -> Logger.Level {
        let label = label.lowercased()
        let level: Logger.Level? = filters.read { filters in filters[label] }
        if let level {
            return level
        }

        let defaultLevel = defaultLevel
        return filters.write { filters in
            for (key, value) in filters where label.hasPrefix(key) {
                filters[label] = value
                return value
            }
            filters[label] = defaultLevel
            return defaultLevel
        }
    }
}
