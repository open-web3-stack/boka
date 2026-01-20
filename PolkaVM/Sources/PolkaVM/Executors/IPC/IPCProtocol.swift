import Foundation
import TracingUtils

private let logger = Logger(label: "IPCProtocol")

/// IPC protocol utilities for message framing and encoding/decoding
enum IPCProtocol {
    /// Message format: [4 bytes length][JSON message]
    static let lengthPrefixSize = 4

    /// Encode a message with length prefix
    static func encodeMessage(_ message: IPCMessage) throws -> Data {
        // Encode message to JSON
        let encoder = JSONEncoder()
        let messageData = try encoder.encode(message)

        // Create length prefix
        let length = UInt32(messageData.count)
        var lengthData = Data()
        withUnsafeBytes(of: length.littleEndian) {
            lengthData.append(Data($0))
        }

        // Combine: [length][message]
        var result = lengthData
        result.append(messageData)

        return result
    }

    /// Decode a message from data (returns message and remaining data)
    static func decodeMessage(_ data: Data) throws -> (IPCMessage, Data)? {
        // Need at least length prefix
        guard data.count >= lengthPrefixSize else {
            return nil
        }

        // Read length
        let lengthData = data[0..<lengthPrefixSize]
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        // Check we have complete message
        let totalSize = Int(length) + lengthPrefixSize
        guard data.count >= totalSize else {
            return nil
        }

        // Extract message payload
        let messageData = data[lengthPrefixSize..<totalSize]

        // Decode JSON
        let decoder = JSONDecoder()
        let message = try decoder.decode(IPCMessage.self, from: messageData)

        // Return message and remaining data
        let remainingData = data.count > totalSize ? Data(data[totalSize...]) : Data()
        return (message, remainingData)
    }

    /// Encode specific payload to JSON Data
    static func encodePayload<T: Codable>(_ payload: T) throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(payload)
    }

    /// Decode specific payload from JSON Data
    static func decodePayload<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    /// Create execute request message
    static func createExecuteRequest(
        requestId: UInt32,
        blob: Data,
        pc: UInt32,
        gas: UInt64,
        argumentData: Data?,
        executionMode: ExecutionMode
    ) throws -> Data {
        let request = IPCExecuteRequest(
            blob: blob,
            pc: pc,
            gas: gas,
            argumentData: argumentData,
            executionMode: executionMode.rawValue
        )

        let payload = try encodePayload(request)
        let message = IPCMessage(type: .executeRequest, requestId: requestId, payload: payload)
        return try encodeMessage(message)
    }

    /// Parse execute request from message
    static func parseExecuteRequest(_ message: IPCMessage) throws -> IPCExecuteRequest {
        guard message.type == .executeRequest else {
            throw IPCError.invalidMessageType
        }

        guard let payload = message.payload else {
            throw IPCError.missingPayload
        }

        return try decodePayload(IPCExecuteRequest.self, from: payload)
    }

    /// Create execute response message
    static func createExecuteResponse(
        requestId: UInt32,
        exitReason: ExitReason,
        gasUsed: UInt64,
        outputData: Data?,
        errorMessage: String? = nil
    ) throws -> Data {
        let response = IPCExecuteResponse(
            exitReasonCode: exitReason.toUInt64(),
            gasUsed: gasUsed,
            outputData: outputData,
            errorMessage: errorMessage
        )

        let payload = try encodePayload(response)
        let message = IPCMessage(type: .executeResponse, requestId: requestId, payload: payload)
        return try encodeMessage(message)
    }

    /// Parse execute response from message
    static func parseExecuteResponse(_ message: IPCMessage) throws -> IPCExecuteResponse {
        guard message.type == .executeResponse else {
            throw IPCError.invalidMessageType
        }

        guard let payload = message.payload else {
            throw IPCError.missingPayload
        }

        return try decodePayload(IPCExecuteResponse.self, from: payload)
    }

    /// Create error message
    static func createErrorMessage(
        requestId: UInt32,
        errorType: IPCErrorMessage.ErrorType,
        message: String
    ) throws -> Data {
        let errorMsg = IPCErrorMessage(errorType: errorType, message: message)
        let payload = try encodePayload(errorMsg)
        let ipcMessage = IPCMessage(type: .error, requestId: requestId, payload: payload)
        return try encodeMessage(ipcMessage)
    }
}

/// IPC-related errors
enum IPCError: Error {
    case invalidMessageType
    case missingPayload
    case malformedMessage
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Int)  // errno
    case readFailed(Int)   // errno
    case timeout
    case unexpectedEOF
}
