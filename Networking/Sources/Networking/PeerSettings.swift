public struct PeerSettings: Sendable {
    public var maxBuilderConnections: Int
}

extension PeerSettings {
    public static let defaultSettings = PeerSettings(maxBuilderConnections: 20)
}
