public struct SafePointer: ~Copyable, Sendable {
    public let ptr: SendableOpaquePointer
    private let free: @Sendable (_ ptr: OpaquePointer) -> Void

    public var value: OpaquePointer {
        ptr.value
    }

    public init(ptr: OpaquePointer, free: @Sendable @escaping (OpaquePointer) -> Void) {
        self.ptr = ptr.asSendable
        self.free = free
    }

    deinit { free(ptr.value) }
}
