use ark_ec_vrfs::{prelude::ark_serialize, suites::bandersnatch::edwards as bandersnatch};
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use bandersnatch::{Public, RingContext, Secret};

use crate::bandersnatch_vrfs::{
    ietf_vrf_sign, ietf_vrf_verify, ring_context, ring_vrf_sign, ring_vrf_verify, RingCommitment,
};

// MARK: Secret

#[no_mangle]
pub extern "C" fn secret_new(seed: *const u8, seed_len: usize, out_ptr: *mut *mut Secret) -> isize {
    if seed.is_null() || out_ptr.is_null() {
        return 1;
    }
    let seed_bytes = unsafe { std::slice::from_raw_parts(seed, seed_len) };
    let secret = Box::new(Secret::from_seed(seed_bytes));
    unsafe {
        *out_ptr = Box::into_raw(secret);
    }
    0
}

#[no_mangle]
pub extern "C" fn secret_free(secret: *mut Secret) {
    if !secret.is_null() {
        unsafe {
            drop(Box::from_raw(secret));
        }
    }
}

// MARK: Public

#[no_mangle]
pub extern "C" fn public_new_from_secret(
    secret: *const Secret,
    out_ptr: *mut *mut Public,
) -> isize {
    if secret.is_null() || out_ptr.is_null() {
        return 1;
    }
    let secret: &Secret = unsafe { &*secret };

    let public = Box::new(secret.public());
    unsafe {
        *out_ptr = Box::into_raw(public);
    }
    0
}

// public_new_from_data
#[no_mangle]
pub extern "C" fn public_new_from_data(
    data: *const u8,
    len: usize,
    out_ptr: *mut *mut Public,
) -> isize {
    if data.is_null() || out_ptr.is_null() {
        return 1;
    }
    let data_slice = unsafe { std::slice::from_raw_parts(data, len) };
    let public = match Public::deserialize_compressed(data_slice) {
        Ok(public) => Box::new(public),
        Err(_) => return 2,
    };
    unsafe { *out_ptr = Box::into_raw(public) };
    0
}

#[no_mangle]
pub extern "C" fn public_free(public: *mut Public) {
    if !public.is_null() {
        unsafe {
            drop(Box::from_raw(public));
        }
    }
}

#[no_mangle]
pub extern "C" fn public_serialize_compressed(
    public: *const Public,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if public.is_null() || out.is_null() {
        return 1;
    }
    if out_len < 32 {
        return 2;
    }
    let public: &Public = unsafe { &*public };
    let mut out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match public.serialize_compressed(&mut out_slice) {
        Ok(_) => 0,
        Err(_) => 3,
    }
}

// MARK: RingContext

#[no_mangle]
pub extern "C" fn ring_context_new(size: usize, out_ptr: *mut *mut RingContext) -> isize {
    if out_ptr.is_null() {
        return 1;
    }
    let ctx = ring_context(size);
    if let Some(ctx) = ctx {
        unsafe {
            *out_ptr = Box::into_raw(Box::new(ctx));
        }
        return 0;
    }
    2
}

#[no_mangle]
pub extern "C" fn ring_context_free(ctx: *mut RingContext) {
    if !ctx.is_null() {
        unsafe {
            drop(Box::from_raw(ctx));
        }
    }
}

// MARK: Prover

/// out is 784 bytes
#[no_mangle]
pub extern "C" fn prover_ring_vrf_sign(
    secret: *const Secret,
    ring: *const Public,
    ring_len: usize,
    prover_idx: usize,
    ctx: *const RingContext,
    vrf_input_data: *const u8,
    vrf_input_len: usize,
    aux_data: *const u8,
    aux_data_len: usize,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if secret.is_null()
        || ring.is_null()
        || ctx.is_null()
        || vrf_input_data.is_null()
        || aux_data.is_null()
        || out.is_null()
    {
        return 1;
    }
    if out_len < 784 {
        return 2;
    }
    let secret: &Secret = unsafe { &*secret };
    let ring_slice = unsafe { std::slice::from_raw_parts(ring, ring_len) };
    let ctx: &RingContext = unsafe { &*ctx };
    let vrf_input_slice = unsafe { std::slice::from_raw_parts(vrf_input_data, vrf_input_len) };
    let aux_data_slice = unsafe { std::slice::from_raw_parts(aux_data, aux_data_len) };
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match ring_vrf_sign(
        secret,
        ring_slice,
        prover_idx,
        ctx,
        vrf_input_slice,
        aux_data_slice,
        out_slice,
    ) {
        Ok(_) => 0,
        Err(_) => 1,
    }
}

/// out is 96 bytes
#[no_mangle]
pub extern "C" fn prover_ietf_vrf_sign(
    secret: *const Secret,
    vrf_input_data: *const u8,
    vrf_input_len: usize,
    aux_data: *const u8,
    aux_data_len: usize,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if secret.is_null() || vrf_input_data.is_null() || aux_data.is_null() || out.is_null() {
        return 1;
    }
    if out_len < 96 {
        return 2;
    }
    let secret: &Secret = unsafe { &*secret };
    let vrf_input_slice = unsafe { std::slice::from_raw_parts(vrf_input_data, vrf_input_len) };
    let aux_data_slice = unsafe { std::slice::from_raw_parts(aux_data, aux_data_len) };
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match ietf_vrf_sign(secret, vrf_input_slice, aux_data_slice, out_slice) {
        Ok(_) => 0,
        Err(_) => 1,
    }
}

// MARK: Verifier

#[no_mangle]
pub extern "C" fn ring_commitment_new_from_ring(
    ring: *const Public,
    ring_len: usize,
    ctx: *const RingContext,
    out: *mut *mut RingCommitment,
) -> isize {
    if ring.is_null() || ctx.is_null() || out.is_null() {
        return 1;
    }
    let ring_slice = unsafe { std::slice::from_raw_parts(ring, ring_len) };
    let ctx: &RingContext = unsafe { &*ctx };
    // Backend currently requires the wrapped type (plain affine points)
    let pts: Vec<_> = ring_slice.iter().map(|pk| pk.0).collect();
    let verifier_key = ctx.verifier_key(&pts);
    let commitment = verifier_key.commitment();
    unsafe {
        *out = Box::into_raw(Box::new(commitment));
    }
    0
}

#[no_mangle]
pub extern "C" fn ring_commitment_new_from_data(
    data: *const u8,
    len: usize,
    out: *mut *mut RingCommitment,
) -> isize {
    if data.is_null() || out.is_null() {
        return 1;
    }
    let data_slice = unsafe { std::slice::from_raw_parts(data, len) };
    let commitment = match RingCommitment::deserialize_compressed(data_slice) {
        Ok(commitment) => Box::new(commitment),
        Err(_) => return 2,
    };
    unsafe { *out = Box::into_raw(commitment) };
    0
}

#[no_mangle]
pub extern "C" fn ring_commitment_free(commitment: *mut RingCommitment) {
    if !commitment.is_null() {
        unsafe {
            drop(Box::from_raw(commitment));
        }
    }
}

/// Ring Commitment: the Bandersnatch ring root in GP
///
/// out is 144 bytes
#[no_mangle]
pub extern "C" fn ring_commitment_serialize(
    commitment: *const RingCommitment,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if commitment.is_null() || out.is_null() {
        return 1;
    }
    if out_len < 144 {
        return 2;
    }
    let commitment: &RingCommitment = unsafe { &*commitment };
    let mut out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match commitment.serialize_compressed(&mut out_slice) {
        Ok(_) => 0,
        Err(_) => 3,
    }
}

/// out is 32 bytes
#[no_mangle]
pub extern "C" fn verifier_ring_vrf_verify(
    ctx: *const RingContext,
    commitment: *const RingCommitment,
    vrf_input_data: *const u8,
    vrf_input_len: usize,
    aux_data: *const u8,
    aux_data_len: usize,
    signature: *const u8,
    signature_len: usize,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if ctx.is_null()
        || commitment.is_null()
        || vrf_input_data.is_null()
        || aux_data.is_null()
        || signature.is_null()
        || out.is_null()
    {
        return 1;
    }
    if out_len < 32 {
        return 2;
    }
    let ctx: &RingContext = unsafe { &*ctx };
    let commitment: &RingCommitment = unsafe { &*commitment };
    let vrf_input_slice = unsafe { std::slice::from_raw_parts(vrf_input_data, vrf_input_len) };
    let aux_data_slice = unsafe { std::slice::from_raw_parts(aux_data, aux_data_len) };
    let signature_slice = unsafe { std::slice::from_raw_parts(signature, signature_len) };
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match ring_vrf_verify(
        ctx,
        commitment,
        vrf_input_slice,
        aux_data_slice,
        signature_slice,
        out_slice,
    ) {
        Ok(_) => 0,
        Err(_) => 1,
    }
}

/// out is 32 bytes
#[no_mangle]
pub extern "C" fn verifier_ietf_vrf_verify(
    public: *const Public,
    vrf_input_data: *const u8,
    vrf_input_len: usize,
    aux_data: *const u8,
    aux_data_len: usize,
    signature: *const u8,
    signature_len: usize,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if public.is_null()
        || vrf_input_data.is_null()
        || aux_data.is_null()
        || signature.is_null()
        || out.is_null()
    {
        return 1;
    }
    if out_len < 32 {
        return 2;
    }
    let public: &Public = unsafe { &*public };
    let vrf_input_slice = unsafe { std::slice::from_raw_parts(vrf_input_data, vrf_input_len) };
    let aux_data_slice = unsafe { std::slice::from_raw_parts(aux_data, aux_data_len) };
    let signature_slice = unsafe { std::slice::from_raw_parts(signature, signature_len) };
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match ietf_vrf_verify(
        public,
        vrf_input_slice,
        aux_data_slice,
        signature_slice,
        out_slice,
    ) {
        Ok(_) => 0,
        Err(_) => 1,
    }
}
