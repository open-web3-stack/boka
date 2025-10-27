import Foundation

public protocol PublicKeyProtocol: Codable, Hashable, CustomStringConvertible, Sendable {
    func toHexString() -> String
}

public protocol SecretKeyProtocol: Sendable {
    associatedtype PublicKey: PublicKeyProtocol
    init(from seed: Data32) throws

    var publicKey: PublicKey { get }
}

public protocol KeyType: Sendable {
    associatedtype SecretKey: SecretKeyProtocol
}

extension PublicKeyProtocol {
    public func equals(rhs: any PublicKeyProtocol) -> Bool {
        guard let rhsValue = rhs as? Self else {
            return false
        }
        return self == rhsValue
    }
}
