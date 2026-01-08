import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "HostCalls.Debug")

// MARK: - Debug

/// A host call for passing a debugging message from the service/authorizer to the hosting environment for logging to the node operator.
public class Log: HostCall {
    public static var identifier: UInt8 { 100 }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    public func gasCost(state _: VMState) -> Gas {
        Gas(10)
    }

    public enum Level: UInt32, Codable {
        case error = 0
        case warn = 1
        case info = 2
        case debug = 3
        case trace = 4

        var description: String {
            switch self {
            case .error: "ERROR"
            case .warn: "WARN"
            case .info: "INFO"
            case .debug: "DEBUG"
            case .trace: "TRACE"
            }
        }
    }

    public struct Details: Codable {
        public let time: String
        public let level: Level
        public let target: Data?
        public let message: Data
        public let core: CoreIndex?
        public let service: ServiceIndex?

        public var json: JSON {
            JSON.dictionary([
                "time": .string(time),
                "level": .string(level.description),
                "message": .string(String(data: message, encoding: .utf8) ?? "invalid string"),
                "target": target != nil ? .string(String(data: target!, encoding: .utf8) ?? "invalid string") : .null,
                "service": service != nil ? .string(String(service!)) : .null,
                "core": core != nil ? .string(String(core!)) : .null,
            ])
        }

        public var str: String {
            var result = time + " \(level.description)"
            if let core {
                result += "@\(core)"
            }
            if let service {
                result += "#\(service)"
            }
            if let target {
                result += " \(String(data: target, encoding: .utf8) ?? "invalid string")"
            }
            result += " \(String(data: message, encoding: .utf8) ?? "invalid string")"

            return result
        }
    }

    public let core: CoreIndex?
    public let service: ServiceIndex?

    public init(core: CoreIndex? = nil, service: ServiceIndex? = nil) {
        self.core = core
        self.service = service
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt32] = state.readRegisters(in: 7 ..< 12)
        let level = regs[0]
        let target = regs[1] == 0 && regs[2] == 0 ? nil : try? state.readMemory(address: regs[1], length: Int(regs[2]))
        let message = try? state.readMemory(address: regs[3], length: Int(regs[4]))

        let time = Self.dateFormatter.string(from: Date())

        let details = Details(
            time: time,
            level: Level(rawValue: level) ?? .debug,
            target: target,
            message: message ?? Data(),
            core: core,
            service: service
        )

        switch level {
        case 0:
            logger.error(Logger.Message(stringLiteral: details.str))
        case 1:
            logger.warning(Logger.Message(stringLiteral: details.str))
        case 2:
            logger.info(Logger.Message(stringLiteral: details.str))
        case 3:
            logger.debug(Logger.Message(stringLiteral: details.str))
        case 4:
            logger.trace(Logger.Message(stringLiteral: details.str))
        default:
            logger.error("Invalid log level: \(level)")
        }

        // always return WHAT
        state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHAT.rawValue)
    }
}
