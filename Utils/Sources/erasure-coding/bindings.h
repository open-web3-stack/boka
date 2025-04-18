/* Warning, this file is auto generated by cbindgen. Don't modify this manually. */

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct Shard Shard;

intptr_t shard_new(const uint8_t *data, uintptr_t data_len, uint32_t index, struct Shard **out);

void shard_free(struct Shard *shard);

intptr_t shard_get_data(const struct Shard *shard, const uint8_t **out_data);

intptr_t shard_get_index(const struct Shard *shard, uint32_t *out_index);

intptr_t reed_solomon_encode(const uint8_t *const *original,
                             uintptr_t original_count,
                             uintptr_t recovery_count,
                             uintptr_t shard_size,
                             uint8_t **out_recovery);

intptr_t reed_solomon_recovery(uintptr_t original_count,
                               uintptr_t recovery_count,
                               const struct Shard *const *recovery_shards,
                               uintptr_t recovery_len,
                               uintptr_t shard_size,
                               uint8_t **out_original);
