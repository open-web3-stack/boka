/* Warning, this file is auto generated by cbindgen. Don't modify this manually. */

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct Public Public;
typedef struct Secret Secret;
typedef struct RingContext RingContext;
typedef struct RingCommitment RingCommitment;


intptr_t secret_new(const uint8_t *seed, uintptr_t seed_len, Secret **out_ptr);

intptr_t secret_output(const Secret *secret,
                       const uint8_t *input,
                       uintptr_t input_len,
                       uint8_t *out,
                       uintptr_t out_len);

void secret_free(Secret *secret);

intptr_t public_new_from_secret(const Secret *secret, Public **out_ptr);

intptr_t public_new_from_data(const uint8_t *data, uintptr_t len, Public **out_ptr);

void public_free(Public *public_);

intptr_t public_serialize_compressed(const Public *public_, uint8_t *out, uintptr_t out_len);

intptr_t ring_context_new(uintptr_t size, RingContext **out_ptr);

void ring_context_free(RingContext *ctx);

/**
 * out is 784 bytes
 */
intptr_t prover_ring_vrf_sign(const Secret *secret,
                              const Public *const *ring,
                              uintptr_t ring_len,
                              uintptr_t prover_idx,
                              const RingContext *ctx,
                              const uint8_t *vrf_input_data,
                              uintptr_t vrf_input_len,
                              const uint8_t *aux_data,
                              uintptr_t aux_data_len,
                              uint8_t *out,
                              uintptr_t out_len);

/**
 * out is 96 bytes
 */
intptr_t prover_ietf_vrf_sign(const Secret *secret,
                              const uint8_t *vrf_input_data,
                              uintptr_t vrf_input_len,
                              const uint8_t *aux_data,
                              uintptr_t aux_data_len,
                              uint8_t *out,
                              uintptr_t out_len);

intptr_t ring_commitment_new_from_ring(const Public *const *ring,
                                       uintptr_t ring_len,
                                       const RingContext *ctx,
                                       RingCommitment **out);

intptr_t ring_commitment_new_from_data(const uint8_t *data, uintptr_t len, RingCommitment **out);

void ring_commitment_free(RingCommitment *commitment);

/**
 * Ring Commitment: the Bandersnatch ring root in GP
 *
 * out is 144 bytes
 */
intptr_t ring_commitment_serialize(const RingCommitment *commitment,
                                   uint8_t *out,
                                   uintptr_t out_len);

/**
 * out is 32 bytes
 */
intptr_t verifier_ring_vrf_verify(const RingContext *ctx,
                                  const RingCommitment *commitment,
                                  const uint8_t *vrf_input_data,
                                  uintptr_t vrf_input_len,
                                  const uint8_t *aux_data,
                                  uintptr_t aux_data_len,
                                  const uint8_t *signature,
                                  uintptr_t signature_len,
                                  uint8_t *out,
                                  uintptr_t out_len);

/**
 * out is 32 bytes
 */
intptr_t verifier_ietf_vrf_verify(const Public *public_,
                                  const uint8_t *vrf_input_data,
                                  uintptr_t vrf_input_len,
                                  const uint8_t *aux_data,
                                  uintptr_t aux_data_len,
                                  const uint8_t *signature,
                                  uintptr_t signature_len,
                                  uint8_t *out,
                                  uintptr_t out_len);

/**
 * out is 32 bytes
 */
intptr_t get_ietf_signature_output(const uint8_t *input,
                                   uintptr_t input_len,
                                   uint8_t *out,
                                   uintptr_t out_len);
