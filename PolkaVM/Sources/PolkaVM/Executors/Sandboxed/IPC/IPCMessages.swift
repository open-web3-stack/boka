import Foundation

/// IPC message types for communication between host and child process
enum IPCMessageType: UInt8, Codable {
    case executeRequest = 1
    case executeResponse = 2
    case error = 3
    case heartbeat = 4
    case hostCallRequest = 5
    case hostCallResponse = 6
}

/// Request to execute a PolkaVM program
struct IPCExecuteRequest: Codable {
    let blob: Data
    let pc: UInt32
    let gas: UInt64
    let argumentData: Data?
    let executionMode: UInt8  // Encoded ExecutionMode flags
}

/// Response from VM execution
struct IPCExecuteResponse: Codable {
    let exitReasonCode: UInt64  // ExitReason.toUInt64()
    let gasUsed: UInt64
    let outputData: Data?
    let errorMessage: String?

    /// Convert to ExitReason
    func toExitReason() -> ExitReason {
        return ExitReason.fromUInt64(exitReasonCode)
    }
}

/// Error message from child process
struct IPCErrorMessage: Codable {
    let errorType: ErrorType
    let message: String

    enum ErrorType: UInt8, Codable {
        case deserialization = 1
        case execution = 2
        case security = 3
        case unknown = 4
    }
}

/// Heartbeat message for health monitoring
struct IPCHeartbeat: Codable {
    let timestamp: UInt64
    let status: Status

    enum Status: UInt8, Codable {
        case ready = 1
        case busy = 2
        case error = 3
    }
}

/// Request for host call from child process
struct IPCHostCallRequest: Codable {
    let callIndex: UInt32
    let registersData: Data  // Serialized register state
}

/// Response to host call from host process
struct IPCHostCallResponse: Codable {
    let outcomeCode: UInt64  // Encoded ExecOutcome
    let registersData: Data? // Updated register state
}

/// Generic IPC message wrapper
struct IPCMessage: Codable {
    let type: IPCMessageType
    let requestId: UInt32
    let payload: Data?  // JSON-encoded specific message

    init(type: IPCMessageType, requestId: UInt32, payload: Data? = nil) {
        self.type = type
        self.requestId = requestId
        self.payload = payload
    }
}
