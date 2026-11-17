import Foundation

/// Compilation-only costs. Sparse tables use a sorted PC array alongside their costs.
struct JITGasCosts {
    enum Representation {
        case automatic, dense, sparse
    }

    let values: [UInt64]
    let starts: [UInt32]

    init(program: ProgramCode, representation: Representation = .automatic) {
        let sparse: Bool = switch representation {
        case .automatic:
            program.basicBlockIndices.count <= program.code.count / 8
        case .dense:
            false
        case .sparse:
            true
        }
        if sparse {
            starts = program.basicBlockIndices.sorted()
            values = starts.map { program.getBlockGasCosts(pc: $0).value }
        } else {
            starts = []
            var costs = Array(repeating: UInt64(0), count: program.code.count)
            for pc in program.basicBlockIndices {
                costs[Int(pc)] = program.getBlockGasCosts(pc: pc).value
            }
            values = costs
        }
    }
}
