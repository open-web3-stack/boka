import Foundation
import TracingUtils

private let logger = Logger(label: "Scheduler")

// TODO: make a scheduler protocol so we can mock it
public class DispatchQueueScheduler {
    private let timeslotPeriod: UInt32
    private let timeProvider: TimeProvider
    private let queue = DispatchQueue(label: "boka.scheduler.queue", attributes: .concurrent)

    public init(timeslotPeriod: UInt32, timeProvider: TimeProvider) {
        self.timeslotPeriod = timeslotPeriod
        self.timeProvider = timeProvider
    }

    @discardableResult
    public func schedule(delay: TimeInterval, repeats: Bool = false, task: @escaping () -> Void) -> DispatchSourceTimer {
        logger.trace("scheduling task in \(delay) seconds, repeats: \(repeats)")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay, repeating: repeats ? delay : .infinity)
        timer.setEventHandler(handler: task)
        timer.resume()
        return timer
    }

    @discardableResult
    public func schedule(at: TimeslotIndex, task: @escaping () -> Void) -> DispatchSourceTimer {
        let deadline = timeslotToTime(timeslot: at)
        logger.trace("scheduling task at timeslot \(at), delay: \(Double(deadline.uptimeNanoseconds) / 1_000_000_000) seconds")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: deadline, repeating: .infinity)
        timer.setEventHandler(handler: task)
        timer.resume()
        return timer
    }

    private func timeslotToTime(timeslot: TimeslotIndex) -> DispatchTime {
        let seconds = timeslot * timeslotPeriod
        let now = timeProvider.getTime()
        let ns = UInt64(seconds - now) * 1_000_000_000
        return DispatchTime(uptimeNanoseconds: ns)
    }
}
