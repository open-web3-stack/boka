#include <asmjit/a64.h>
#include <asmjit/asmjit.h>
#include <iostream>
#include <stdio.h>

#include "helper.hh"

using namespace asmjit;

CppHelper::CppHelper() { std::cout << "CppHelper constructor" << std::endl; }
CppHelper::~CppHelper() { std::cout << "CppHelper destructor" << std::endl; }

// Signature of the generated function.
typedef int (*Func)(void);

void CppHelper::test() const {
    // Runtime designed for JIT - it holds relocated functions and controls their
    // lifetime.
    JitRuntime rt;

    // Holds code and relocation information during code generation.
    CodeHolder code;

    // Code holder must be initialized before it can be used. The simples way to
    // initialize it is to use 'Environment' from JIT runtime, which matches the
    // target architecture, operating system, ABI, and other important properties.
    code.init(rt.environment(), rt.cpuFeatures());

    // Emitters can emit code to CodeHolder - let's create 'x86::Assembler', which
    // can emit either 32-bit (x86) or 64-bit (x86_64) code. The following line
    // also attaches the assembler to CodeHolder, which calls 'code.attach(&a)'
    // implicitly.
    a64::Assembler a(&code);

    //   // Use the x86::Assembler to emit some code to .text section in
    //   CodeHolder: a.mov(x86::eax, 1);  // Emits 'mov eax, 1' - moves one to
    //   'eax' register. a.ret();             // Emits 'ret'        - returns from
    //   a function.

    // Use the a64::Assembler to emit some code to .text section in CodeHolder:
    a.mov(a64::x0, 1); // Emits 'mov x0, 1' - moves one to 'x0' register.
    a.ret(a64::x30);   // Emits 'ret'        - returns from a function.

    // 'x86::Assembler' is no longer needed from here and can be destroyed or
    // explicitly detached via 'code.detach(&a)' - which detaches an attached
    // emitter from code holder.

    // Now add the generated code to JitRuntime via JitRuntime::add(). This
    // function would copy the code from CodeHolder into memory with executable
    // permission and relocate it.
    Func fn;
    Error err = rt.add(&fn, &code);

    // It's always a good idea to handle errors, especially those returned from
    // the Runtime.
    if (err) {
        printf("AsmJit failed: %s\n", DebugUtils::errorAsString(err));
        return;
    }

    // CodeHolder is no longer needed from here and can be safely destroyed. The
    // runtime now holds the relocated function, which we have generated, and
    // controls its lifetime. The function will be freed with the runtime, so it's
    // necessary to keep the runtime around.
    //
    // Use 'code.reset()' to explicitly free CodeHolder's content when necessary.

    printf("Code size: %zu bytes\n", code.codeSize());

    // Execute the generated function and print the resulting '1', which it moves
    // to 'eax'.
    int result = fn();
    printf("%d\n", result);

    // All classes use RAII, all resources will be released before `main()`
    // returns, the generated function can be, however, released explicitly if you
    // intend to reuse or keep the runtime alive, which you should in a
    // production-ready code.
    rt.release(fn);
}
