public struct SafePointer: ~Copyable, Sendable {
    let ptr: SendableOpaquePointer
    let free: @Sendable (_ ptr: OpaquePointer) -> Void
    deinit { free(ptr.value) }
}
