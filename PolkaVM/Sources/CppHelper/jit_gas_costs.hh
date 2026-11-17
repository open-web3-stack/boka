#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>

// Non-owning, compilation-only view. Target lookups never disturb the forward cursor.
class JITGasCostView {
    const uint64_t* values;
    const uint32_t* starts;
    size_t count;
    size_t codeSize;
    size_t cursor = 0;

public:
    JITGasCostView(const uint64_t* values, const uint32_t* starts, size_t count, size_t codeSize)
        : values(values), starts(starts), count(count), codeSize(codeSize) {}

    uint64_t at(uint32_t pc) const {
        if (pc >= codeSize) return 0;
        if (!count) return values[pc];
        const auto it = std::lower_bound(starts, starts + count, pc);
        return it != starts + count && *it == pc ? values[it - starts] : 0;
    }

    // Both native compilers emit instructions in ascending PC order.
    uint64_t sequential(uint32_t pc) {
        if (!count) return pc < codeSize ? values[pc] : 0;
        while (cursor < count && starts[cursor] < pc) ++cursor;
        return cursor < count && starts[cursor] == pc ? values[cursor] : 0;
    }

    uint64_t containing(uint32_t pc) const {
        if (pc >= codeSize) return 0;
        if (!count) {
            while (pc > 0 && !values[pc]) --pc;
            return values[pc];
        }
        const auto it = std::upper_bound(starts, starts + count, pc);
        return it == starts ? 0 : values[it - starts - 1];
    }
};
