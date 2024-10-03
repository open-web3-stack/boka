import ConsoleKit
import Logging
import Utils

private struct SourceLocationFragment: LoggerFragment {
    public func write(_ record: inout LogRecord, to output: inout FragmentOutput) {
        output += "(\(record.file):\(record.line))".consoleText(ConsoleStyle(color: .brightBlack))
        output.needsSeparator = true
    }
}

private struct InnerFragment: LoggerFragment {
    func write(_ record: inout LogRecord, to output: inout FragmentOutput) {
        output += "\(levelName(record.level))".consoleText(levelStyle(record.level))
        output += "\t| "
        output += record.label.consoleText(ConsoleStyle(color: .brightBlack))
        output += "\t|"
        output.needsSeparator = true
    }

    private func levelStyle(_ level: Logger.Level) -> ConsoleStyle {
        switch level {
        case .trace: ConsoleStyle(color: .brightBlack)
        case .debug: .plain
        case .info, .notice: .info
        case .warning: .warning
        case .error: .error
        case .critical: ConsoleStyle(color: .brightRed)
        }
    }

    private func levelName(_ level: Logger.Level) -> String {
        switch level {
        case .trace: "TRACE"
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTICE"
        case .warning: "WARN"
        case .error: "ERROR"
        case .critical: "CRITIC"
        }
    }
}

public final class LogFragment: LoggerFragment {
    private let defaultLevel: Logger.Level
    private let filters: ThreadSafeContainer<[String: Logger.Level]>
    private let inner: LoggerFragment

    public init(defaultLevel: Logger.Level = .info, filters: [String: Logger.Level] = [:]) {
        self.defaultLevel = defaultLevel
        self.filters = .init(filters)
        inner = TimestampFragment()
            .and(InnerFragment().separated(" "))
            .and(MessageFragment().separated(" "))
            .and(MetadataFragment().separated(" "))
            .and(SourceLocationFragment().separated(" ").maxLevel(.debug))
    }

    public func levelFor(label: String) -> Logger.Level {
        let level: Logger.Level? = filters.read { filters in filters[label] }
        if let level {
            return level
        }

        let defaultLevel = defaultLevel
        return filters.mutate { filters in
            for (key, value) in filters where label.hasPrefix(key) {
                filters[label] = value
                return value
            }
            filters[label] = defaultLevel
            return defaultLevel
        }
    }

    public func hasContent(record: inout LogRecord) -> Bool {
        let level = levelFor(label: record.label)
        return record.level > level
    }

    public func write(_ record: inout LogRecord, to: inout FragmentOutput) {
        let level = levelFor(label: record.label)
        if record.level < level {
            return
        }
        inner.write(&record, to: &to)
    }

    public static func parse(from: String) -> (LogFragment, Logger.Level)? {
        var defaultLevel: Logger.Level?
        var lowestLevel = Logger.Level.critical
        var filters: [String: Logger.Level] = [:]
        let parts = from.split(separator: ",")
        for part in parts {
            let entry = part.split(separator: "=")
            switch entry.count {
            case 1:
                defaultLevel = Logger.Level(String(entry[0]))
            case 2:
                guard let level = Logger.Level(String(entry[1])) else {
                    return nil
                }
                filters[String(entry[0])] = level
                lowestLevel = min(lowestLevel, level)
            default:
                return nil
            }
        }

        return (Self(defaultLevel: defaultLevel ?? .info, filters: filters), min(lowestLevel, defaultLevel ?? .critical))
    }
}
