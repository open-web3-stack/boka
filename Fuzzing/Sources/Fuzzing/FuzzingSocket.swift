import Blockchain
import Codec
import Foundation
import TracingUtils

#if canImport(Darwin)
    import Darwin

    private let platformClose = Darwin.close
    private let platformConnect = Darwin.connect
    private let platformSockStream = SOCK_STREAM
#elseif canImport(Glibc)
    import Glibc

    private let platformClose = Glibc.close
    private let platformConnect = Glibc.connect
    private let platformSockStream = Int32(SOCK_STREAM.rawValue)
#else
    #error("Unsupported platform")
#endif

private let logger = Logger(label: "FuzzingSocket")

public enum FuzzingSocketError: Error {
    case socketCreationFailed
    case socketBindFailed
    case socketListenFailed
    case socketConnectFailed
    case acceptFailed
    case receiveFailed
    case sendFailed
    case invalidMessageSize
}

public class FuzzingSocket {
    private let socketPath: String
    private var socketFd: Int32 = -1
    private let config: ProtocolConfigRef
    private var isServer: Bool = false

    public init(socketPath: String, config: ProtocolConfigRef) {
        self.socketPath = socketPath
        self.config = config
    }

    deinit {
        if socketFd >= 0 {
            _ = platformClose(socketFd)
            socketFd = -1
        }
        if isServer {
            unlink(socketPath)
        }
    }

    /// Create a Unix domain socket and bind it to the specified path
    public func create() throws {
        isServer = true

        // Create Unix domain socket
        socketFd = socket(AF_UNIX, platformSockStream, 0)

        guard socketFd >= 0 else {
            throw FuzzingSocketError.socketCreationFailed
        }

        // Remove existing socket file if present
        unlink(socketPath)

        // Bind socket
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        var sunPath = addr.sun_path
        withUnsafeMutablePointer(to: &sunPath) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: addr.sun_path)) { cPtr in
                _ = strcpy(cPtr, socketPath)
            }
        }
        addr.sun_path = sunPath

        let bindResult = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(socketFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            _ = platformClose(socketFd)
            throw FuzzingSocketError.socketBindFailed
        }

        // Listen for connections
        guard listen(socketFd, 1) == 0 else {
            _ = platformClose(socketFd)
            throw FuzzingSocketError.socketListenFailed
        }
    }

    /// Accept a client connection
    public func acceptConnection() throws -> FuzzingSocketConnection {
        guard socketFd >= 0 else {
            throw FuzzingSocketError.socketCreationFailed
        }

        let clientFd = accept(socketFd, nil, nil)
        guard clientFd >= 0 else {
            throw FuzzingSocketError.acceptFailed
        }

        return FuzzingSocketConnection(fd: clientFd, config: config)
    }

    /// Connect to socket
    public func connect() throws -> FuzzingSocketConnection {
        socketFd = socket(AF_UNIX, platformSockStream, 0)

        guard socketFd >= 0 else {
            throw FuzzingSocketError.socketCreationFailed
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        var sunPath = addr.sun_path
        withUnsafeMutablePointer(to: &sunPath) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: addr.sun_path)) { cPtr in
                _ = strcpy(cPtr, socketPath)
            }
        }
        addr.sun_path = sunPath

        let result = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                platformConnect(socketFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            _ = platformClose(socketFd)
            throw FuzzingSocketError.socketConnectFailed
        }

        return FuzzingSocketConnection(fd: socketFd, config: config)
    }
}

/// Represents an active socket connection for message exchange
public class FuzzingSocketConnection {
    private let fd: Int32
    private let config: ProtocolConfigRef

    init(fd: Int32, config: ProtocolConfigRef) {
        self.fd = fd
        self.config = config
    }

    deinit {
        self.close()
    }

    public func receiveMessage() throws -> FuzzingMessage? {
        // Read message length (4 bytes, little endian)
        var lengthBuffer = [UInt8](repeating: 0, count: 4)
        var totalRead = 0

        // Handle partial reads for length
        while totalRead < 4 {
            let bytesRead = recv(fd, &lengthBuffer[totalRead], 4 - totalRead, 0)
            if bytesRead == 0 {
                if totalRead == 0 {
                    return nil // Clean connection close
                } else {
                    logger.error("Connection closed unexpectedly mid-read (got \(totalRead)/4 bytes)")
                    throw FuzzingSocketError.receiveFailed
                }
            }
            if bytesRead < 0 {
                logger.error("Error receiving length: \(String(cString: strerror(errno)))")
                throw FuzzingSocketError.receiveFailed
            }
            totalRead += bytesRead
        }

        // Parse message length (little endian)
        let messageLength = lengthBuffer.withUnsafeBytes { $0.load(as: UInt32.self) }

        // Sanity check message length
        guard messageLength > 0 else {
            throw FuzzingSocketError.invalidMessageSize
        }

        // Read message data
        var messageBuffer = [UInt8](repeating: 0, count: Int(messageLength))
        totalRead = 0

        // Handle partial reads for message data
        while totalRead < messageLength {
            let bytesRead = recv(fd, &messageBuffer[totalRead], Int(messageLength) - totalRead, 0)
            if bytesRead <= 0 {
                logger.error("Error receiving message data: \(String(cString: strerror(errno)))")
                throw FuzzingSocketError.receiveFailed
            }
            totalRead += bytesRead
        }

        let data = Data(messageBuffer)

        // Try to decode the message, catching decoding errors
        do {
            return try JamDecoder.decode(FuzzingMessage.self, from: data, withConfig: config)
        } catch {
            logger.error("Failed to decode: \(error)")
            // Return an error message instead of throwing, to keep connection alive
            return .error("Failed to decode: \(error)")
        }
    }

    public func sendMessage(_ message: FuzzingMessage) throws {
        let data = try JamEncoder.encode(message)
        let length = UInt32(data.count)

        // Create complete message buffer (length + data)
        var completeBuffer = Data()
        completeBuffer.append(contentsOf: withUnsafeBytes(of: length) { Data($0) })
        completeBuffer.append(data)

        // Try to send complete message in one system call
        let messageArray = Array(completeBuffer)
        let totalSize = completeBuffer.count

        let bytesSent = messageArray.withUnsafeBufferPointer { ptr in
            send(fd, ptr.baseAddress!, totalSize, 0)
        }

        if bytesSent != totalSize {
            let error = bytesSent < 0 ? String(cString: strerror(errno)) : "Partial send (\(bytesSent)/\(totalSize))"
            logger.error("Failed to send complete message: \(error)")
            throw FuzzingSocketError.sendFailed
        }
    }

    public func close() {
        guard fd >= 0 else { return }
        _ = platformClose(fd)
    }
}
