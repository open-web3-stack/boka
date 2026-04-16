#pragma once

#include <cstddef>
#include <unordered_map>

namespace asmjit {
    inline namespace v1_21 {
        class JitRuntime;
    }
}

struct RuntimeContext {
    asmjit::JitRuntime* _Nonnull runtime;
    std::unordered_map<void*, std::pair<void**, size_t>> dispatcherTables;

    RuntimeContext();
    ~RuntimeContext();
};
