import msquic

public typealias QuicStatus = UInt32
public typealias QuicApiTable = QUIC_API_TABLE
public typealias HQuic = HQUIC
public typealias QuicBuffer = QUIC_BUFFER
public typealias QuicSettings = QUIC_SETTINGS
public typealias QuicCredentialConfig = QUIC_CREDENTIAL_CONFIG
public typealias QuicCertificateFile = QUIC_CERTIFICATE_FILE
public typealias QuicListenerEvent = QUIC_LISTENER_EVENT
public typealias QuicConnectionEvent = QUIC_CONNECTION_EVENT
public typealias QuicStreamEvent = QUIC_STREAM_EVENT
public typealias ConnectionCallback = @convention(c) (
    OpaquePointer?, UnsafeMutableRawPointer?, UnsafePointer<QuicConnectionEvent>?
) -> QuicStatus
public typealias StreamCallback = @convention(c) (
    OpaquePointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<QuicStreamEvent>?
) -> QuicStatus
public typealias ServerListenerCallback = @convention(c) (
    OpaquePointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<QuicListenerEvent>?
) -> QuicStatus
