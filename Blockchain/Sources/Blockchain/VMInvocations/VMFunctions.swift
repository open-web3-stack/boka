public struct VMFunctions: AccumulateFunction, OnTransferFunction, RefineFunction, IsAuthorizedFunction, Sendable {
    public static let shared = VMFunctions()
}
