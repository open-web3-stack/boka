import msquic

public class Networking {
    public class Config {
        public let listenAddress: String
        public let port: Int

        public init(listenAddress: String, port: Int) {
            self.listenAddress = listenAddress
            self.port = port
        }
    }

    init() {}
}
