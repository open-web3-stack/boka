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
    private let inner: LoggerFragment

    public init() {
        inner = TimestampFragment()
            .and(InnerFragment().separated(" "))
            .and(MessageFragment().separated(" "))
            .and(MetadataFragment().separated(" "))
            .and(SourceLocationFragment().separated(" ").maxLevel(.debug))
    }

    public func hasContent(record: inout LogRecord) -> Bool {
        inner.hasContent(record: &record)
    }

    public func write(_ record: inout LogRecord, to: inout FragmentOutput) {
        inner.write(&record, to: &to)
    }
}
