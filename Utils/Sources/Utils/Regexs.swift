import Foundation

public enum RegexsError: Error {
    case invalidFormat
    case invalidPort
}

public enum Regexs {
    public static func parseAddress(_ address: String) throws -> (ip: String, port: Int) {
        let ipWithPortPattern = #"^((?:[0-9]{1,3}\.){3}[0-9]{1,3}|(?:\[[0-9a-fA-F:]+\])):([0-9]{1,5})$"#
        let ipWithPortRegex = try NSRegularExpression(pattern: ipWithPortPattern)
        let matches = ipWithPortRegex.matches(in: address, range: NSRange(location: 0, length: address.utf16.count))

        guard let match = matches.first, match.numberOfRanges == 3 else {
            throw RegexsError.invalidFormat
        }

        let ipRange = Range(match.range(at: 1), in: address)!
        let portRange = Range(match.range(at: 2), in: address)!

        var ip = String(address[ipRange])
        let portString = String(address[portRange])

        if ip.hasPrefix("["), ip.hasSuffix("]") {
            ip.removeFirst()
            ip.removeLast()
        }

        guard let port = Int(portString), port > 0 else {
            throw RegexError.invalidPort
        }

        return (ip, port)
    }
}
