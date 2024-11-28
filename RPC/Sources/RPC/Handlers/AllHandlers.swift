enum AllHandlers {
    static let handlers: [any RPCHandler.Type] =
        ChainHandlers.handlers +
        SystemHandlers.handlers +
        TelemetryHandlers.handlers +
        RPCHandlers.handlers

    static func getHandlers(source: ChainDataSource & SystemDataSource & TelemetryDataSource) -> [any RPCHandler] {
        ChainHandlers.getHandlers(source: source) +
            SystemHandlers.getHandlers(source: source) +
            TelemetryHandlers.getHandlers(source: source) +
            RPCHandlers.getHandlers(source: handlers)
    }
}
