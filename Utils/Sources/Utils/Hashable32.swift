public protocol Hashable32 {
    func hash() -> Data32
}

extension Hashable where Self: Hashable32 {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hash())
    }
}
