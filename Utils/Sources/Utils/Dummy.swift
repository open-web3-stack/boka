/// return a dummy value of the type
/// this is mostly used during initial development or testing
/// should be avoided in production code
public protocol Dummy: HasConfig {
    static func dummy(config: Config) -> Self
}
