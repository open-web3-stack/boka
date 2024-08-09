/* Warning, this file is auto generated by cbindgen. Don't modify this manually. */

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define POINT_SIZE 2
#define SUBSHARD_POINTS 6
#define TOTAL_SHARDS 1026
#define SUBSHARD_SIZE 12

typedef uint16_t ChunkIndex;



#define MAX_CHUNKS 16384

/**
 * Fix segment size.
 */
#define SEGMENT_SIZE 4096

/**
 * Fix number of shards and subshards.
 */
#define N_SHARDS 342

/**
 * The number of time the erasure coded shards we want.
 */
#define N_REDUNDANCY 2

/**
 * Subshard uses some temp memory, so these should be used multiple time instead of allocating.
 */
typedef struct SubShardDecoder SubShardDecoder;

/**
 * Subshard uses some temp memory, so these should be used multiple time instead of allocating.
 */
typedef struct SubShardEncoder SubShardEncoder;

/**
 * Fixed size segment of a larger data.
 * Data is padded when unaligned with
 * the segment size.
 */
typedef struct CSegment {
  /**
   * Fix size chunk of data. Length is `SEGMENT_SIZE``
   */
  uint8_t *data;
  /**
   * The index of this segment against its full data.
   */
  uint32_t index;
} CSegment;

typedef struct SegmentTuple {
  uint8_t index;
  struct CSegment segment;
} SegmentTuple;

/**
 * Result of the reconstruct.
 */
typedef struct ReconstructResult {
  struct SegmentTuple *segments;
  uintptr_t num_segments;
  uintptr_t num_decodes;
} ReconstructResult;

typedef struct SubShardTuple {
  uint8_t seg_index;
  ChunkIndex chunk_index;
  uint8_t subshard[12];
} SubShardTuple;

/**
 * Subshard (points in sequential orders).
 */
typedef uint8_t SubShard[SUBSHARD_SIZE];

/**
 * Initializes a new SubShardEncoder.
 */
struct SubShardEncoder *subshard_encoder_new(void);

/**
 * Frees the SubShardEncoder.
 */
void subshard_encoder_free(struct SubShardEncoder *encoder);

/**
 * Constructs erasure-coded chunks from segments.
 *
 * A chunk is a group of subshards `[[u8; 12]; TOTAL_SHARDS]`.
 *
 * out_chunks is N chunks `[[u8; 12]; TOTAL_SHARDS]` flattened to 1 dimensional u8 array.
 * out_len is N * TOTAL_SHARDS
 */
void subshard_encoder_construct(struct SubShardEncoder *encoder,
                                const struct CSegment *segments,
                                uintptr_t num_segments,
                                bool *success,
                                uint8_t *out_chunks,
                                uintptr_t *out_len);

/**
 * Initializes a new SubShardDecoder.
 */
struct SubShardDecoder *subshard_decoder_new(void);

/**
 * Frees the SubShardDecoder.
 */
void subshard_decoder_free(struct SubShardDecoder *decoder);

void reconstruct_result_free(struct ReconstructResult *result);

/**
 * Reconstructs data from a list of subshards.
 */
struct ReconstructResult *subshard_decoder_reconstruct(struct SubShardDecoder *decoder,
                                                       const struct SubShardTuple *subshards,
                                                       uintptr_t num_subshards,
                                                       bool *success);
