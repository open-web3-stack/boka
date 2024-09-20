import PolkaVM

extension HostCallFunction {
    public static func hasEnoughGas(state: VMState) -> Bool {
        state.getGas() >= gasCost
    }
}
