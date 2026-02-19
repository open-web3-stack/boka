#include "MacOSSandboxSupport.h"
#include <stddef.h>

#if defined(__APPLE__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include <sandbox.h>
#pragma clang diagnostic pop

int boka_apply_macos_sandbox(char **errorbuf) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return sandbox_init(kSBXProfilePureComputation, SANDBOX_NAMED, errorbuf);
#pragma clang diagnostic pop
}

void boka_free_macos_sandbox_error(char *errorbuf) {
    if (errorbuf == NULL) {
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    sandbox_free_error(errorbuf);
#pragma clang diagnostic pop
}

#else

int boka_apply_macos_sandbox(char **errorbuf) {
    if (errorbuf != NULL) {
        *errorbuf = NULL;
    }

    return -1;
}

void boka_free_macos_sandbox_error(char *errorbuf) {
    (void)errorbuf;
}

#endif
