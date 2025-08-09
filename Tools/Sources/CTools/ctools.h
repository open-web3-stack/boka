#pragma once

#include <fcntl.h>

/**
 * Emit machine code that:
 *   - Loads 32-bit values from (dataAddr + reg1Offset) and (dataAddr + reg2Offset)
 *   - Adds them
 *   - Stores the 32-bit result at (dataAddr + regDestOffset)
 *   - Returns (ret)
 *
 *  codePtr:        pointer to the code buffer (writable/executable)
 *
 * Returns the number of bytes of machine code emitted.
 */
 int emitAddExample(void *codePtr);

int ctools_shm_open(const char *name, int oflag, mode_t mode);
