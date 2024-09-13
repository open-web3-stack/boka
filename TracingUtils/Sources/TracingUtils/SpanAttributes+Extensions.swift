extension SpanAttributes {
    public var blockHash: SpanAttributeConvertible? {
        get {
            self["blockHash"]
        }
        set {
            self["blockHash"] = newValue
        }
    }
}
