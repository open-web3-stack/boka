extension SpanAttributes {
    public var blockHash: SpanAttributeConvertible? {
        get {
            self["blockHash"]
        }
        set {
            self["blockHash"] = newValue
        }
    }

    public var event: SpanAttributeConvertible? {
        get {
            self["event"]
        }
        set {
            self["event"] = newValue
        }
    }
}
