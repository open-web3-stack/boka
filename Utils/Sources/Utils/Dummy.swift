/// return a dummy value of the type
/// this is mostly used during initial development or testing
/// should be avoided in production code
public protocol Dummy {
    static var dummy: Self { get }
}
