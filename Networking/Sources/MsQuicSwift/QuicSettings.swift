import msquic

public typealias QuicSettings = QUIC_SETTINGS

extension QuicSettings {
    public static let defaultSettings = {
        var settings = QuicSettings()
        settings.IdleTimeoutMs = 60000
        settings.IsSet.IdleTimeoutMs = 1
        settings.ServerResumptionLevel = 2 // QUIC_SERVER_RESUME_AND_ZERORTT
        settings.IsSet.ServerResumptionLevel = 1
        settings.PeerBidiStreamCount = 100
        settings.IsSet.PeerBidiStreamCount = 1
        return settings
    }()
}
