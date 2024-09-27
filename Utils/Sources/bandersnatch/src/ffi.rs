use ark_ec_vrfs::{prelude::ark_serialize, suites::bandersnatch::edwards as bandersnatch};
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use bandersnatch::{Public, RingContext, Secret};

use crate::bandersnatch_vrfs::{
    ietf_vrf_sign, ietf_vrf_verify, ring_context, ring_vrf_sign, ring_vrf_verify, vrf_input_point,
    RingCommitment,
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
pub extern "C" fn secret_output(
    secret: *const Secret,
    input: *const u8,
    input_len: usize,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if secret.is_null() || input.is_null() || out.is_null() {
        return 1;
    }
    if out_len < 32 {
        return 2;
    }
    let secret: &Secret = unsafe { &*secret };
    let input_slice = unsafe { std::slice::from_raw_parts(input, input_len) };
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    let input_point = vrf_input_point(input_slice);
    let input_point = if let Ok(input_point) = input_point {
        input_point
    } else {
        return 3;
    };

    let output = secret.output(input_point);
    out_slice.copy_from_slice(&output.hash()[..32]);
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
// TODO: if provided data is invalid (e.g. all zeros), return padding points instead
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
    ring: *const *const Public,
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
    ring: *const *const Public,
    ring_len: usize,
    ctx: *const RingContext,
    out: *mut *mut RingCommitment,
) -> isize {
    if ring.is_null() || ctx.is_null() || out.is_null() {
        return 1;
    }
    let ring_slice: &[*const Public] = unsafe { std::slice::from_raw_parts(ring, ring_len) };
    let ctx: &RingContext = unsafe { &*ctx };
    // Backend currently requires the wrapped type (plain affine points)
    let pts: Vec<_> = unsafe { ring_slice.iter().map(|pk| (*(*pk)).0).collect() };
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
        Err(_) => 3,
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
        Err(_) => 3,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hex_literal::hex;

    #[test]
    fn test_ring_vrf_sign() {
        let ring_data = vec![
            hex!("5e465beb01dbafe160ce8216047f2155dd0569f058afd52dcea601025a8d161d"),
            hex!("3d5e5a51aab2b048f8686ecd79712a80e3265a114cc73f14bdb2a59233fb66d0"),
            hex!("aa2b95f7572875b0d0f186552ae745ba8222fc0b5bd456554bfe51c68938f8bc"),
            hex!("7f6190116d118d643a98878e294ccf62b509e214299931aad8ff9764181a4e33"),
            hex!("48e5fcdce10e0b64ec4eebd0d9211c7bac2f27ce54bca6f7776ff6fee86ab3e3"),
            hex!("f16e5352840afb47e206b5c89f560f2611835855cf2e6ebad1acc9520a72591d"),
        ];

        let signature = hex!("b342bf8f6fa69c745daad2e99c92929b1da2b840f67e5e8015ac22dd1076343ea95c5bb4b69c197bfdc1b7d2f484fe455fb19bba7e8d17fcaf309ba5814bf54f3a74d75b408da8d3b99bf07f7cde373e4fd757061b1c99e0aac4847f1e393e892b566c14a7f8643a5d976ced0a18d12e32c660d59c66c271332138269cb0fe9c2462d5b3c1a6e9f5ed330ff0d70f64218010ff337b0b69b531f916c67ec564097cd842306df1b4b44534c95ff4efb73b17a14476057fdf8678683b251dc78b0b94712179345c794b6bd99aa54b564933651aee88c93b648e91a613c87bc3f445fff571452241e03e7d03151600a6ee259051a23086b408adec7c112dd94bd8123cf0bed88fddac46b7f891f34c29f13bf883771725aa234d398b13c39fd2a871894f1b1e2dbc7fffbc9c65c49d1e9fd5ee0da133bef363d4ebebe63de2b50328b5d7e020303499d55c07cae617091e33a1ee72ba1b65f940852e93e2905fdf577adcf62be9c74ebda9af59d3f11bece8996773f392a2b35693a45a5a042d88a3dc816b689fe596762d4ea7c6024da713304f56dc928be6e8048c651766952b6c40d0f48afc067ca7cbd77763a2d4f11e88e16033b3343f39bf519fe734db8a139d148ccead4331817d46cf469befa64ae153b5923869144dfa669da36171c20e1f757ed5231fa5a08827d83f7b478ddfb44c9bceb5c6c920b8761ff1e3edb03de48fb55884351f0ac5a7a1805b9b6c49c0529deb97e994deaf2dfd008825e8704cdc04b621f316b505fde26ab71b31af7becbc1154f9979e43e135d35720b93b367bedbe6c6182bb6ed99051f28a3ad6d348ba5b178e3ea0ec0bb4a03fe36604a9eeb609857f8334d3b4b34867361ed2ff9163acd9a27fa20303abe9fc29f2d6c921a8ee779f7f77d940b48bc4fce70a58eed83a206fb7db4c1c7ebe7658603495bb40f6a581dd9e235ba0583165b1569052f8fb4a3e604f2dd74ad84531c6b96723c867b06b6fdd1c4ba150cf9080aa6bbf44cc29041090973d56913b9dc755960371568ef1cf03f127fe8eca209db5d18829f5bfb5826f98833e3f42472b47fad995a9a8bb0e41a1df45ead20285a8");

        let ring = ring_data
            .iter()
            .map(|data| {
                let mut ptr: *mut Public = std::ptr::null_mut();
                public_new_from_data(data.as_ptr(), data.len(), &mut ptr);
                ptr
            })
            .collect::<Vec<_>>();
        let vrf_input_data = hex!("6a616d5f7469636b65745f7365616cbb30a42c1e62f0afda5f0a4e8a562f7a13a24cea00ee81917b86b89e801314aa01");
        let aux_data = vec![];

        let mut ctx_ptr: *mut RingContext = std::ptr::null_mut();
        assert_eq!(ring_context_new(6, &mut ctx_ptr), 0);

        let mut commitment_ptr: *mut RingCommitment = std::ptr::null_mut();
        assert_eq!(
            ring_commitment_new_from_ring(
                ring.as_ptr() as *const *const Public,
                ring.len(),
                ctx_ptr,
                &mut commitment_ptr
            ),
            0
        );

        let mut output = [0u8; 32];

        assert_eq!(
            verifier_ring_vrf_verify(
                ctx_ptr,
                commitment_ptr,
                vrf_input_data.as_ptr(),
                vrf_input_data.len(),
                aux_data.as_ptr(),
                aux_data.len(),
                signature.as_ptr(),
                signature.len(),
                output.as_mut_ptr(),
                output.len()
            ),
            0
        );

        ring_commitment_free(commitment_ptr);
        ring_context_free(ctx_ptr);
        for ptr in ring.iter() {
            public_free(*ptr);
        }
    }
}
