import msquic

public typealias QuicSettings = QUIC_SETTINGS

extension QuicSettings {
    public static let defaultSettings = {
        var settings = QuicSettings()
        settings.IdleTimeoutMs = 300_000 / 60 // 5 minutes
        settings.IsSet.IdleTimeoutMs = 1
        settings.ServerResumptionLevel = 2 // QUIC_SERVER_RESUME_AND_ZERORTT
        settings.IsSet.ServerResumptionLevel = 1
        settings.PeerBidiStreamCount = 100
        settings.IsSet.PeerBidiStreamCount = 1
        return settings
    }()
}
