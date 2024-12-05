public enum AllHandlers {
    public static let handlers: [any RPCHandler.Type] =
        ChainHandlers.handlers +
        SystemHandlers.handlers +
        StateHandlers.handlers +
        TelemetryHandlers.handlers +
        RPCHandlers.handlers

    public static func getHandlers(source: ChainDataSource & SystemDataSource & TelemetryDataSource) -> [any RPCHandler] {
        var handlers = ChainHandlers.getHandlers(source: source)
        handlers.append(contentsOf: SystemHandlers.getHandlers(source: source))
        handlers.append(contentsOf: StateHandlers.getHandlers(source: source))
        handlers.append(contentsOf: TelemetryHandlers.getHandlers(source: source))
        handlers.append(contentsOf: RPCHandlers.getHandlers(source: Self.handlers))
        return handlers
    }
}