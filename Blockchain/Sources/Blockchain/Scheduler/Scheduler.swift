import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Scheduler")

public final class Cancellable: Sendable, Hashable {
    private let fn: @Sendable () -> Void
    public init(_ fn: @escaping @Sendable () -> Void) {
        self.fn = fn
    }

    public func cancel() {
        fn()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: Cancellable, rhs: Cancellable) -> Bool {
        lhs === rhs
    }
}

public protocol Scheduler: Sendable {
    var timeProvider: TimeProvider { get }

    func scheduleImpl(
        delay: TimeInterval,
        repeats: Bool,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)?,
    ) -> Cancellable
}

extension Scheduler {
    func schedule(
        id: UniqueId = "",
        delay: TimeInterval,
        repeats: Bool = false,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)? = nil,
    ) -> Cancellable {
        guard delay >= 0 else {
            logger.error("scheduling task with negative delay", metadata: ["id": "\(id)", "delay": "\(delay)", "repeats": "\(repeats)"])
            return Cancellable {}
        }
        logger.trace("scheduling task", metadata: ["id": "\(id)", "delay": "\(delay)", "repeats": "\(repeats)"])
        let cancellable = scheduleImpl(delay: delay, repeats: repeats, task: {
            logger.trace("executing task", metadata: ["id": "\(id)"])
            await task()
        }, onCancel: onCancel)
        return Cancellable {
            logger.trace("cancelling task", metadata: ["id": "\(id)"])
            cancellable.cancel()
        }
    }
}

extension Scheduler {
    public func getTime() -> UInt32 {
        timeProvider.getTime()
    }
}
