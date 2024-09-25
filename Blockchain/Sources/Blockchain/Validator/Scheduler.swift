import Dispatch
import Foundation

// TODO: make a scheduler protocol so we can mock it
public class Scheduler {
    private let timeslotPeriod: UInt32
    private let offset: UInt32
    private let queue = DispatchQueue(label: "boka.scheduler.queue", attributes: .concurrent)

    public init(timeslotPeriod: UInt32, offset: UInt32) {
        self.timeslotPeriod = timeslotPeriod
        self.offset = offset
    }

    public func schedule(delay: TimeInterval, repeats: Bool = false, task: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay, repeating: repeats ? delay : .infinity)
        timer.setEventHandler(handler: task)
        timer.resume()
        return timer
    }

    public func scheduler(at: TimeslotIndex, task: @escaping () -> Void) -> DispatchSourceTimer {
        let delay = timeslotToTime(timeslot: at)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: delay, repeating: .infinity)
        timer.setEventHandler(handler: task)
        timer.resume()
        return timer
    }

    private func timeslotToTime(timeslot: TimeslotIndex) -> DispatchTime {
        let seconds = timeslot * timeslotPeriod + offset
        let ns = UInt64(seconds) * NSEC_PER_SEC
        return DispatchTime(uptimeNanoseconds: ns)
    }
}
