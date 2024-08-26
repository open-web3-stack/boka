import Blake2

public protocol Hashing: ~Copyable {
    init()
    mutating func update(_ data: some DataPtrRepresentable)
    consuming func finalize() -> Data32
}
