import Foundation

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
