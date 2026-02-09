#pragma once

#include <asmjit/core.h>
#include <asmjit/a64.h>

// Static register allocation for PolkaVM JIT
// These are architecture-specific register mappings

// x86_64 (AMD64) register allocation
namespace x64_reg {
    // VM state registers
    constexpr int VM_GLOBAL_STATE_PTR = 0;  // r15 - VM global state pointer

    // Guest VM registers
    constexpr int GUEST_REG0 = 1;           // rax
    constexpr int GUEST_REG1 = 2;           // rdx
    constexpr int GUEST_REG2 = 3;           // rbx
    constexpr int GUEST_REG3 = 4;           // rbp
    constexpr int GUEST_REG4 = 5;           // rsi
    constexpr int GUEST_REG5 = 6;           // rdi
    constexpr int GUEST_REG6 = 7;           // r8
    constexpr int GUEST_REG7 = 8;           // r9
    constexpr int GUEST_REG8 = 9;           // r10
    constexpr int GUEST_REG9 = 10;          // r11
    constexpr int GUEST_REG10 = 11;         // r12
    constexpr int GUEST_REG11 = 12;         // r13
    constexpr int GUEST_REG12 = 13;         // r14

    // Temporary register used by the recompiler
    constexpr int TEMP_REG = 14;            // rcx
}

// AArch64 (ARM64) register allocation
namespace a64_reg {
    // VM state registers
    constexpr int VM_GLOBAL_STATE_PTR = 0;  // x28 - VM global state pointer

    // Guest VM registers
    constexpr int GUEST_REG0 = 1;           // x0
    constexpr int GUEST_REG1 = 2;           // x1
    constexpr int GUEST_REG2 = 3;           // x2
    constexpr int GUEST_REG3 = 4;           // x3
    constexpr int GUEST_REG4 = 5;           // x4
    constexpr int GUEST_REG5 = 6;           // x5
    constexpr int GUEST_REG6 = 7;           // x6
    constexpr int GUEST_REG7 = 8;           // x7
    constexpr int GUEST_REG8 = 9;           // x9
    constexpr int GUEST_REG9 = 10;          // x10
    constexpr int GUEST_REG10 = 11;         // x11
    constexpr int GUEST_REG11 = 12;         // x12
    constexpr int GUEST_REG12 = 13;         // x19
    constexpr int GUEST_REG13 = 14;         // x20
    constexpr int GUEST_REG14 = 15;         // x21
    constexpr int GUEST_REG15 = 16;         // x22

    // Temporary register used by the recompiler
    constexpr int TEMP_REG = 17;            // x8
}

// Physical register mapping constants for x86_64
namespace x64_reg_id {
    // Register IDs for x86_64 (matching asmjit::x86::Gp::kId* constants)
    constexpr int kIdAx = 0;   // rax
    constexpr int kIdCx = 1;   // rcx
    constexpr int kIdDx = 2;   // rdx
    constexpr int kIdBx = 3;   // rbx
    constexpr int kIdSp = 4;   // rsp
    constexpr int kIdBp = 5;   // rbp
    constexpr int kIdSi = 6;   // rsi
    constexpr int kIdDi = 7;   // rdi
    constexpr int kIdR8 = 8;   // r8
    constexpr int kIdR9 = 9;   // r9
    constexpr int kIdR10 = 10; // r10
    constexpr int kIdR11 = 11; // r11
    constexpr int kIdR12 = 12; // r12
    constexpr int kIdR13 = 13; // r13
    constexpr int kIdR14 = 14; // r14
    constexpr int kIdR15 = 15; // r15
}



// Physical register mapping functions
// These functions map logical VM registers to physical CPU registers
namespace reg_map {
    // Get the physical register for a VM register index in x86_64
    inline int getPhysicalRegX64(int vmReg) {
        switch (vmReg) {
            case x64_reg::VM_GLOBAL_STATE_PTR: return x64_reg_id::kIdR15; // r15
            case x64_reg::GUEST_REG0:         return x64_reg_id::kIdAx;  // rax
            case x64_reg::GUEST_REG1:         return x64_reg_id::kIdDx;  // rdx
            case x64_reg::GUEST_REG2:         return x64_reg_id::kIdBx;  // rbx
            case x64_reg::GUEST_REG3:         return x64_reg_id::kIdBp;  // rbp
            case x64_reg::GUEST_REG4:         return x64_reg_id::kIdSi;  // rsi
            case x64_reg::GUEST_REG5:         return x64_reg_id::kIdDi;  // rdi
            case x64_reg::GUEST_REG6:         return x64_reg_id::kIdR8;  // r8
            case x64_reg::GUEST_REG7:         return x64_reg_id::kIdR9;  // r9
            case x64_reg::GUEST_REG8:         return x64_reg_id::kIdR10; // r10
            case x64_reg::GUEST_REG9:         return x64_reg_id::kIdR11; // r11
            case x64_reg::GUEST_REG10:        return x64_reg_id::kIdR12; // r12
            case x64_reg::GUEST_REG11:        return x64_reg_id::kIdR13; // r13
            case x64_reg::GUEST_REG12:        return x64_reg_id::kIdR14; // r14
            case x64_reg::TEMP_REG:           return x64_reg_id::kIdCx;  // rcx
            default: return x64_reg_id::kIdAx; // Default to rax
        }
    }

    // Get the physical register for a VM register index in AArch64
    inline int getPhysicalRegA64(int vmReg) {
        switch (vmReg) {
            case a64_reg::VM_GLOBAL_STATE_PTR: return 28; // x28
            case a64_reg::GUEST_REG0:         return 0;  // x0
            case a64_reg::GUEST_REG1:         return 1;  // x1
            case a64_reg::GUEST_REG2:         return 2;  // x2
            case a64_reg::GUEST_REG3:         return 3;  // x3
            case a64_reg::GUEST_REG4:         return 4;  // x4
            case a64_reg::GUEST_REG5:         return 5;  // x5
            case a64_reg::GUEST_REG6:         return 6;  // x6
            case a64_reg::GUEST_REG7:         return 7;  // x7
            case a64_reg::GUEST_REG8:         return 9;  // x9
            case a64_reg::GUEST_REG9:         return 10; // x10
            case a64_reg::GUEST_REG10:        return 11; // x11
            case a64_reg::GUEST_REG11:        return 12; // x12
            case a64_reg::GUEST_REG12:        return 19; // x19
            case a64_reg::GUEST_REG13:        return 20; // x20
            case a64_reg::GUEST_REG14:        return 21; // x21
            case a64_reg::GUEST_REG15:        return 22; // x22
            case a64_reg::TEMP_REG:           return 8;  // x8
            default: return 0; // Default to x0
        }
    }
}
