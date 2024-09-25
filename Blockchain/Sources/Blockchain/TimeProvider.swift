import Foundation

public protocol TimeProvider: Sendable {
    func getTime() -> UInt32
}

public struct SystemTimeProvider: TimeProvider {
    public init() {}

    public func getTime() -> UInt32 {
        Date().timeIntervalSinceJamCommonEra
    }
}

public struct FixedTimeProvider: TimeProvider {
    public var time: UInt32

    public init(time: UInt32) {
        self.time = time
    }

    public func getTime() -> UInt32 {
        time
    }
}

extension Date {
    public static var jamCommonEraBeginning: UInt32 {
        // the Jam Common Era: 1200 UTC on January 1, 2024
        // number of seconds since the Unix epoch
        1_704_110_400
    }

    public var timeIntervalSinceJamCommonEra: UInt32 {
        let beginning = Double(Date.jamCommonEraBeginning)
        let now = timeIntervalSince1970
        return UInt32(now - beginning)
    }
}
