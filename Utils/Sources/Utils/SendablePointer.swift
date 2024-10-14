/// A wrapper for pointers that is Sendable.
/// Note: The underlying pointer must be actually threadsafe otherwise bad things will happen.
public struct SendablePointer<T>: @unchecked Sendable {
    public let value: UnsafePointer<T>

    public init(_ value: UnsafePointer<T>) {
        self.value = value
    }
}

extension UnsafePointer {
    public var asSendable: SendablePointer<Pointee> {
        SendablePointer(self)
    }
}

/// A wrapper for opaque pointers that is Sendable.
/// Note: The underlying pointer must be actually threadsafe otherwise bad things will happen.
public struct SendableOpaquePointer: @unchecked Sendable {
    public let value: OpaquePointer

    public init(_ value: OpaquePointer) {
        self.value = value
    }
}

extension OpaquePointer {
    public var asSendable: SendableOpaquePointer {
        SendableOpaquePointer(self)
    }
}
