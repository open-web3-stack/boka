import Foundation
import TracingUtils

private let logger = Logger(label: "Insts ")

extension Instructions {
    enum Constants {
        static let djumpHaltAddress: UInt32 = 0xFFFF_0000
    }

    static func decodeImmediate<T: FixedWidthInteger>(_ data: Data) -> T {
        // The immediate value (as encoded in the code blob) can be at most 4 bytes
        let len = min(data.count, 4)
        if len == 0 {
            return 0
        }
        var value: UInt32 = 0
        for i in 0 ..< len {
            value = value | (UInt32(data[relative: i]) << (8 * i))
        }
        let shift = (4 - len) * 8
        // shift left so that the MSB is the sign bit
        // and then do signed shift right to fill the empty bits using the sign bit
        let signExtendedValue = Int32(bitPattern: value << shift) >> shift
        return T(truncatingIfNeeded: signExtendedValue)
    }

    /// Decode variable-length integer (varint) from data
    /// Varint format: 7 bits per byte, continuation bit (0x80) indicates more bytes
    static func decodeVarint(_ data: Data) -> UInt64 {
        var result: UInt64 = 0
        var shift = 0
        var index = 0
        var foundTerminator = false

        while index < data.count {
            let byte = data[index]
            result |= UInt64(byte & 0x7F) << shift
            index += 1

            if (byte & 0x80) == 0 {
                foundTerminator = true
                break
            }

            shift += 7
            if shift >= 64 {
                logger.error("Varint overflow - value too large")
                return 0
            }
        }

        // Ensure we found a proper terminator before running out of data
        if !foundTerminator {
            logger.error("Varint underflow - data ended without terminator")
            return 0
        }

        return result
    }

    static func decodeImmediate2<T: FixedWidthInteger, U: FixedWidthInteger>(
        _ data: Data,
        divideBy: UInt8 = 1,
        minus: Int = 1,
        startIdx: Int = 0
    ) throws -> (T, U) {
        let lX1 = try Int((data.at(relative: startIdx) / divideBy) & 0b111)
        let lX = min(4, lX1)
        let lY = min(4, max(0, data.count - Int(lX) - minus))

        let start = startIdx + 1
        let vX: T = decodeImmediate(data.subdata(in: data.startIndex + start ..< data.startIndex + (start + lX)))
        let vY: U = decodeImmediate(data.subdata(in: data.startIndex + (start + lX) ..< data.startIndex + (start + lX + lY)))
        return (vX, vY)
    }

    static func isBranchValid(context: ExecutionContext, offset: UInt32) -> Bool {
        let targetPC = context.state.pc &+ offset

        // Check if target is within code bounds
        guard targetPC < UInt32(context.state.program.code.count) else {
            return false
        }

        // Check if target PC is at an instruction boundary using bitmask
        // Per spec pvm.tex line 124, branch targets must be in basicblocks set
        // The bitmask has bit 0 set at instruction boundaries
        return context.state.program.isInstructionBoundary(targetPC)
    }

    static func djump(context: ExecutionContext, target: UInt32) -> ExecOutcome {
        if target == Constants.djumpHaltAddress {
            return .exit(.halt)
        }

        let za = context.config.pvmDynamicAddressAlignmentFactor
        let entrySize = Int(context.state.program.jumpTableEntrySize)
        let numEntries = context.state.program.jumpTable.count

        if target == 0 || target > UInt32(numEntries * za) || Int(target) % za != 0 {
            return .exit(.panic(.invalidDynamicJump))
        }

        let start = ((Int(target) / za) - 1) * entrySize
        let end = start + entrySize
        let jumpTable = context.state.program.jumpTable

        #if DEBUG
            logger.trace("djump start (\(start)) end (\(end))")
        #endif

        guard jumpTable.count >= (end - start), jumpTable.startIndex + end <= jumpTable.endIndex else {
            return .exit(.panic(.invalidDynamicJump))
        }

        var targetAlignedData = jumpTable.subdata(in: jumpTable.startIndex + start ..< jumpTable.startIndex + end)

        #if DEBUG
            logger.trace("djump target data (\(targetAlignedData.map(\.self)))")
        #endif

        let targetAligned: UInt32
        switch entrySize {
        case 1:
            targetAligned = UInt32(targetAlignedData.decodeUInt8())
        case 2:
            targetAligned = UInt32(targetAlignedData.decodeUInt16())
        case 3:
            targetAligned = targetAlignedData.decodeUInt24()
        case 4:
            targetAligned = targetAlignedData.decodeUInt32()
        default:
            guard let decoded: UInt32 = targetAlignedData.decode(length: entrySize) else {
                return .exit(.panic(.invalidDynamicJump))
            }
            targetAligned = decoded
        }

        #if DEBUG
            logger.trace("djump target decoded (\(targetAligned))")
        #endif

        guard context.state.program.basicBlockIndices.contains(targetAligned) else {
            return .exit(.panic(.invalidDynamicJump))
        }

        context.state.updatePC(targetAligned)
        return .continued
    }

    static func decodeRegisters(_ data: Data) throws -> (Registers.Index, Registers.Index) {
        let ra = try Registers.Index(r1: data.at(relative: 0))
        let rb = try Registers.Index(r2: data.at(relative: 0))
        return (ra, rb)
    }

    static func decodeRegisters(_ data: Data) throws -> (Registers.Index, Registers.Index, Registers.Index) {
        let ra = try Registers.Index(r1: data.at(relative: 0))
        let rb = try Registers.Index(r2: data.at(relative: 0))
        let rd = try Registers.Index(r3: data.at(relative: 1))
        return (ra, rb, rd)
    }

    /// Decode two varint-encoded values from data starting at offset
    /// Used for LoadImmJump, LoadImmJumpInd, and BranchImm instructions
    /// - Parameters:
    ///   - data: Instruction bytecode
    ///   - offset: Starting offset for first varint (after register byte)
    /// - Returns: Tuple of (firstValue, secondValue, bytesConsumed)
    static func decodeVarintPair(_ data: Data, offset: Int = 1) throws -> (UInt32, UInt32, Int) {
        var currentOffset = offset
        var bytesConsumed = 0

        // Decode first varint
        var firstValue: UInt64 = 0
        var shift = 0
        var foundTerminator = false
        while currentOffset < data.count {
            let byte = data[currentOffset]
            firstValue |= UInt64(byte & 0x7F) << shift
            bytesConsumed += 1
            currentOffset += 1

            if (byte & 0x80) == 0 {
                foundTerminator = true
                break
            }

            shift += 7
            if shift >= 64 {
                throw InstructionDecodingError.varintOverflow
            }
        }

        guard foundTerminator else {
            throw InstructionDecodingError.insufficientData
        }

        // Decode second varint
        var secondValue: UInt64 = 0
        shift = 0
        foundTerminator = false
        while currentOffset < data.count {
            let byte = data[currentOffset]
            secondValue |= UInt64(byte & 0x7F) << shift
            bytesConsumed += 1
            currentOffset += 1

            if (byte & 0x80) == 0 {
                foundTerminator = true
                break
            }

            shift += 7
            if shift >= 64 {
                throw InstructionDecodingError.varintOverflow
            }
        }

        guard foundTerminator else {
            throw InstructionDecodingError.insufficientData
        }

        return (UInt32(truncatingIfNeeded: firstValue), UInt32(truncatingIfNeeded: secondValue), bytesConsumed)
    }

    /// Decode a single varint-encoded value from data starting at offset
    /// Used for StoreImmInd instructions
    /// - Parameters:
    ///   - data: Instruction bytecode
    ///   - offset: Starting offset for varint (after register byte)
    /// - Returns: Tuple of (value, bytesConsumed)
    static func decodeVarintSingle(_ data: Data, offset: Int = 1) throws -> (UInt64, Int) {
        var currentOffset = offset
        var bytesConsumed = 0
        var value: UInt64 = 0
        var shift = 0
        var foundTerminator = false

        while currentOffset < data.count {
            let byte = data[currentOffset]
            value |= UInt64(byte & 0x7F) << shift
            bytesConsumed += 1
            currentOffset += 1

            if (byte & 0x80) == 0 {
                foundTerminator = true
                break
            }

            shift += 7
            if shift >= 64 {
                throw InstructionDecodingError.varintOverflow
            }
        }

        guard foundTerminator else {
            throw InstructionDecodingError.insufficientData
        }

        return (value, bytesConsumed)
    }

    enum InstructionDecodingError: Swift.Error {
        case varintOverflow
        case insufficientData
    }
}
