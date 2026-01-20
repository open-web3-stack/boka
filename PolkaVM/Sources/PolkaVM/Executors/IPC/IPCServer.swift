import Foundation
import TracingUtils
import Glibc

private let logger = Logger(label: "IPCServer")

/// IPC server for child process to receive requests and send responses
class IPCServer {
    private var fileDescriptor: Int32?
    private var isRunning = false

    init() {}

    /// Set the file descriptor for communication
    func setFileDescriptor(_ fd: Int32) {
        fileDescriptor = fd
    }

    /// Close the file descriptor
    func close() {
        isRunning = false
        if let fd = fileDescriptor {
            Glibc.close(fd)
            fileDescriptor = nil
        }
    }

    /// Run the IPC server loop
    func run(handler: @escaping (IPCExecuteRequest) async throws -> IPCExecuteResponse) async {
        guard let fd = fileDescriptor else {
            logger.error("No file descriptor set")
            return
        }

        isRunning = true

        while isRunning {
            do {
                // Read message
                let message = try await readMessage(from: fd)

                // Handle based on message type
                switch message.type {
                case .executeRequest:
                    await handleExecuteRequest(message, handler: handler)

                case .heartbeat:
                    // Respond to heartbeat
                    let response = IPCMessage(type: .heartbeat, requestId: message.requestId)
                    try? writeMessage(response, to: fd)

                case .error:
                    logger.error("Received error message from host")
                    // Stop running on error
                    isRunning = false

                default:
                    logger.warning("Unknown message type: \(message.type)")
                }

            } catch {
                logger.error("IPC server error: \(error)")
                isRunning = false
            }
        }
    }

    /// Handle execute request
    private func handleExecuteRequest(
        _ message: IPCMessage,
        handler: @escaping (IPCExecuteRequest) async throws -> IPCExecuteResponse
    ) async {
        guard let fd = fileDescriptor else {
            return
        }

        do {
            // Parse request
            let request = try IPCProtocol.parseExecuteRequest(message)

            // Execute request
            let response = try await handler(request)

            // Send response
            let responseData = try IPCProtocol.createExecuteResponse(
                requestId: message.requestId,
                exitReason: response.toExitReason(),
                gasUsed: response.gasUsed,
                outputData: response.outputData,
                errorMessage: response.errorMessage
            )

            try writeData(responseData, to: fd)

        } catch {
            logger.error("Failed to handle execute request: \(error)")

            // Send error response
            do {
                let errorMsg = try IPCProtocol.createErrorMessage(
                    requestId: message.requestId,
                    errorType: .execution,
                    message: "\(error)"
                )
                try? writeData(errorMsg, to: fd)
            } catch {
                logger.error("Failed to send error message: \(error)")
            }
        }
    }

    /// Read message from file descriptor
    private func readMessage(from fd: Int32) async throws -> IPCMessage {
        // Read length prefix (4 bytes)
        let lengthData = try readExactBytes(IPCProtocol.lengthPrefixSize, from: fd)

        let length = lengthData.withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }

        guard length > 0 && length < 1024 * 1024 * 100 else {
            throw IPCError.malformedMessage
        }

        // Read message payload
        let messageData = try readExactBytes(Int(length), from: fd)

        // Decode message
        let decodeResult = try? IPCProtocol.decodeMessage(lengthData + messageData)
        guard let message = decodeResult?.0 else {
            throw IPCError.decodingFailed(NSError(domain: "IPCServer", code: -1))
        }

        return message
    }

    /// Write message to file descriptor
    private func writeMessage(_ message: IPCMessage, to fd: Int32) throws {
        let data = try IPCProtocol.encodeMessage(message)
        try writeData(data, to: fd)
    }

    /// Write data to file descriptor
    private func writeData(_ data: Data, to fd: Int32) throws {
        _ = try data.withUnsafeBytes { rawBuffer in
            guard let baseAddr = rawBuffer.baseAddress else {
                throw IPCError.writeFailed(Int(EINVAL))
            }

            var bytesWritten = 0
            let totalBytes = rawBuffer.count

            while bytesWritten < totalBytes {
                let ptr = baseAddr.advanced(by: bytesWritten)
                let result = ptr.withMemoryRebound(to: UInt8.self, capacity: totalBytes - bytesWritten) {
                    Glibc.write(fd, $0, totalBytes - bytesWritten)
                }

                if result < 0 {
                    let err = errno
                    logger.error("Failed to write to IPC: \(errnoToString(err))")
                    throw IPCError.writeFailed(Int(err))
                }

                bytesWritten += Int(result)
            }

            return bytesWritten
        }
    }

    /// Read exact number of bytes from file descriptor
    private func readExactBytes(_ count: Int, from fd: Int32) throws -> Data {
        var buffer = Data(count: count)
        var bytesRead = 0

        while bytesRead < count {
            try buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddr = rawBuffer.baseAddress else {
                    throw IPCError.readFailed(Int(EINVAL))
                }

                let ptr = baseAddr.advanced(by: bytesRead)
                let result = ptr.withMemoryRebound(to: UInt8.self, capacity: count - bytesRead) {
                    Glibc.read(fd, $0, count - bytesRead)
                }

                if result < 0 {
                    let err = errno
                    logger.error("Failed to read from IPC: \(errnoToString(err))")
                    throw IPCError.readFailed(Int(err))
                }

                if result == 0 {
                    throw IPCError.unexpectedEOF
                }

                bytesRead += Int(result)

                return
            }
        }

        return buffer
    }

    /// Convert errno to string
    private func errnoToString(_ err: Int32) -> String {
        return String(cString: strerror(err))
    }

    deinit {
        close()
    }
}
