public protocol PublicKeyProtocol: Codable, Hashable {}

public protocol SecretKeyProtocol {
    associatedtype PublicKey: PublicKeyProtocol
    init(from seed: Data32) throws

    var publicKey: PublicKey { get }
}

public protocol KeyType {
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
