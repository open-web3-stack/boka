import Blake2
import Foundation

public typealias DataPtrRepresentable = Blake2.DataPtrRepresentable

/// Waiting for NoncopyableGenerics to be available
public protocol Hashing /*: ~Copyable */ {
    init()
    mutating func update(_ data: any DataPtrRepresentable)
    consuming func finalize() -> Data32
}

extension Hashing {
    public static func hash(_ data: (any DataPtrRepresentable)...) -> Data32 {
        var hasher = Self()
        for item in data {
            hasher.update(item)
        }
        return hasher.finalize()
    }
}

extension FixedSizeData: DataPtrRepresentable {
    public typealias Ptr = UnsafeRawBufferPointer

    public func withPtr<R>(
        cb: (UnsafeRawBufferPointer) throws -> R,
    ) rethrows -> R {
        try data.withUnsafeBytes(cb)
    }
}

extension Either: DataPtrRepresentable, PtrRepresentable where Left: DataPtrRepresentable, Right: DataPtrRepresentable,
    Left.Ptr == Right.Ptr
{
    public typealias Ptr = Left.Ptr

    public func withPtr<R>(
        cb: (Left.Ptr) throws -> R,
    ) rethrows -> R {
        switch self {
        case let .left(left):
            try left.withPtr(cb: cb)
        case let .right(right):
            try right.withPtr(cb: cb)
        }
    }
}
