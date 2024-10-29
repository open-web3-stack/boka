import Foundation

public struct PeerId: Sendable, Hashable {
    public let publicKey: Data
    public let address: NetAddr

    public init(publicKey: Data, address: NetAddr) {
        self.publicKey = publicKey
        self.address = address
    }
}
