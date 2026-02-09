#ifndef BOKA_MACOS_SANDBOX_SUPPORT_H
#define BOKA_MACOS_SANDBOX_SUPPORT_H

#ifdef __cplusplus
extern "C" {
#endif

int boka_apply_macos_sandbox(char **errorbuf);
void boka_free_macos_sandbox_error(char *errorbuf);

#ifdef __cplusplus
}
#endif

#endif
