import Utils

protocol Safrole {
    var timeslot: TimeslotIndex { get }
    var entropyPool: (Data32, Data32, Data32, Data32) { get }
}

extension Safrole {}
