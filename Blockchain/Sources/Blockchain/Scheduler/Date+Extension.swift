import Foundation

extension Date {
    public static var jamCommonEraBeginning: UInt32 {
        // the Jam Common Era: 1200 UTC on January 1, 2025
        // number of seconds since the Unix epoch
        1_735_732_800
    }

    public var timeIntervalSinceJamCommonEra: TimeInterval {
        let beginning = Double(Date.jamCommonEraBeginning)
        let now = timeIntervalSince1970
        return now - beginning
    }
}
