import Blake2
import Foundation

// Waiting for NoncopyableGenerics to be available
public protocol Hashing /*: ~Copyable */ {
    init()
    mutating func update(_ data: some DataPtrRepresentable)
    consuming func finalize() -> Data32
}

extension Hashing {
    public static func hash(data: some DataPtrRepresentable) -> Data32 {
        var hasher = Self()
        hasher.update(data)
        return hasher.finalize()
    }
}

extension FixedSizeData: DataPtrRepresentable {
    public typealias Ptr = UnsafeRawBufferPointer

    public func withPtr<R>(
        cb: (UnsafeRawBufferPointer) throws -> R
    ) rethrows -> R {
        try data.withUnsafeBytes(cb)
    }
}

extension Either: DataPtrRepresentable, PtrRepresentable where Left: DataPtrRepresentable, Right: DataPtrRepresentable,
    Left.Ptr == Right.Ptr
{
    public typealias Ptr = Left.Ptr

    public func withPtr<R>(
        cb: (Left.Ptr) throws -> R
    ) rethrows -> R {
        switch self {
        case let .left(left):
            try left.withPtr(cb: cb)
        case let .right(right):
            try right.withPtr(cb: cb)
        }
    }
}
