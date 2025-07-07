/// A default coding key used for types not belong to trivial encoding types
struct DefaultKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) { nil }

    init(for type: (some Any).Type) {
        stringValue = "<\(type)>"
    }
}
