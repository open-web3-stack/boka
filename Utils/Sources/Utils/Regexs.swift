import Foundation

public enum RegexsError: Error {
    case invalidFormat
    case invalidPort
}

public enum Regexs {
    // Combined regex pattern for IP address with port
    public static func parseAddress(_ address: String) throws -> (ip: String, port: Int) {
        let ipv4Pattern = #"(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"#
        let ipv6Pattern =
            #"(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:(?:[0-9A-Fa-f]{1,4}:){1,7}:)|(?:(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4})|(?:(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2})|(?:(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3})|(?:(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4})|(?:(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5})|(?:(?:[0-9A-Fa-f]{1,4}:){1,1}(?::[0-9A-Fa-f]{1,4}){1,6})|(?::(?::[0-9A-Fa-f]{1,4}){1,7}|:))(?:%\w+)?"#
        let ipAddressWithPortPattern = #"(?:(\#(ipv4Pattern))|\[(\#(ipv6Pattern))\]):(\d{1,5})"#

        let regex = try NSRegularExpression(pattern: ipAddressWithPortPattern, options: [])
        let range = NSRange(location: 0, length: address.utf16.count)

        if let match = regex.firstMatch(in: address, options: [], range: range) {
            let ipRange: Range<String.Index>
            if let ipv4Range = Range(match.range(at: 1), in: address) {
                ipRange = ipv4Range
            } else if let ipv6Range = Range(match.range(at: 2), in: address) {
                ipRange = ipv6Range
            } else {
                throw RegexsError.invalidFormat
            }

            let portRange = Range(match.range(at: 3), in: address)!

            let ip = String(address[ipRange])
            let portString = String(address[portRange])

            if let port = Int(portString), (0 ... 65535).contains(port) {
                return (ip, port)
            } else {
                throw RegexsError.invalidPort
            }
        } else {
            throw RegexsError.invalidFormat
        }
    }
}
