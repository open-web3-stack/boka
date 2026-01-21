import Foundation

/// IPC message types for communication between host and child process
public enum IPCMessageType: UInt8, Codable {
    case executeRequest = 1
    case executeResponse = 2
    case error = 3
    case heartbeat = 4
    case hostCallRequest = 5
    case hostCallResponse = 6
}

/// Request to execute a PolkaVM program
public struct IPCExecuteRequest: Codable, Sendable {
    public let blob: Data
    public let pc: UInt32
    public let gas: UInt64
    public let argumentData: Data?
    public let executionMode: UInt8  // Encoded ExecutionMode flags

    public init(blob: Data, pc: UInt32, gas: UInt64, argumentData: Data?, executionMode: UInt8) {
        self.blob = blob
        self.pc = pc
        self.gas = gas
        self.argumentData = argumentData
        self.executionMode = executionMode
    }
}

/// Response from VM execution
public struct IPCExecuteResponse: Codable, Sendable {
    public let exitReasonCode: UInt64  // ExitReason.toUInt64()
    public let gasUsed: UInt64
    public let outputData: Data?
    public let errorMessage: String?

    public init(exitReasonCode: UInt64, gasUsed: UInt64, outputData: Data?, errorMessage: String?) {
        self.exitReasonCode = exitReasonCode
        self.gasUsed = gasUsed
        self.outputData = outputData
        self.errorMessage = errorMessage
    }

    /// Convert to ExitReason
    public func toExitReason() -> ExitReason {
        return ExitReason.fromUInt64(exitReasonCode)
    }
}

/// Error message from child process
public struct IPCErrorMessage: Codable {
    public let errorType: ErrorType
    public let message: String

    public enum ErrorType: UInt8, Codable {
        case deserialization = 1
        case execution = 2
        case security = 3
        case unknown = 4
    }
}

/// Heartbeat message for health monitoring
public struct IPCHeartbeat: Codable {
    public let timestamp: UInt64
    public let status: Status

    public enum Status: UInt8, Codable {
        case ready = 1
        case busy = 2
        case error = 3
    }
}

/// Request for host call from child process
public struct IPCHostCallRequest: Codable {
    public let callIndex: UInt32
    public let registersData: Data  // Serialized register state
}

/// Response to host call from host process
public struct IPCHostCallResponse: Codable {
    public let outcomeCode: UInt64  // Encoded ExecOutcome
    public let registersData: Data? // Updated register state
}

/// Generic IPC message wrapper
public struct IPCMessage: Codable {
    public let type: IPCMessageType
    public let requestId: UInt32
    public let payload: Data?  // JSON-encoded specific message

    public init(type: IPCMessageType, requestId: UInt32, payload: Data? = nil) {
        self.type = type
        self.requestId = requestId
        self.payload = payload
    }
}
