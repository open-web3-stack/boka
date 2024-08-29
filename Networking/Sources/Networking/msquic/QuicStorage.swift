import Foundation

struct QuicConnectionEvent {
    var type: Int
}

struct QuicStorage {
    var conn: HQuic
    var config: HQuic
    var stream: HQuic
}
