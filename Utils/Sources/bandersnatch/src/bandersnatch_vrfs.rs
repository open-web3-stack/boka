// Code copied and modified based on: https://github.com/davxy/bandersnatch-vrfs-spec/blob/470d836ae5c8ee9509892f90cf3eebf21ddf55c2/example/src/main.rs

use ark_ec_vrfs::suites::bandersnatch::edwards as bandersnatch;
use ark_ec_vrfs::{prelude::ark_serialize, suites::bandersnatch::edwards::RingContext};
use bandersnatch::{IetfProof, Input, Output, PcsParams, Public, RingProof, Secret};

use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};

// This is the IETF `Prove` procedure output as described in section 2.2
// of the Bandersnatch VRFs specification
#[derive(CanonicalSerialize, CanonicalDeserialize)]
pub struct IetfVrfSignature {
    output: Output,
    proof: IetfProof,
}

// This is the IETF `Prove` procedure output as described in section 4.2
// of the Bandersnatch VRFs specification
#[derive(CanonicalSerialize, CanonicalDeserialize)]
pub struct RingVrfSignature {
    output: Output,
    // This contains both the Pedersen proof and actual ring proof.
    proof: RingProof,
}

pub fn ring_context(size: usize) -> Option<RingContext> {
    let pcs_params = ring_context_params();
    RingContext::from_srs(size, pcs_params.clone()).ok()
}

fn ring_context_params() -> &'static PcsParams {
    use std::sync::OnceLock;
    static PARAMS: OnceLock<PcsParams> = OnceLock::new();
    PARAMS.get_or_init(|| {
        let buf: &'static [u8] = include_bytes!("../data/zcash-srs-2-11-uncompressed.bin");
        PcsParams::deserialize_uncompressed_unchecked(&mut &buf[..])
            .expect("Static params must be valid")
    })
}

// Construct VRF Input Point from arbitrary data (section 1.2)
pub fn vrf_input_point(vrf_input_data: &[u8]) -> Result<Input, ()> {
    let point =
        <bandersnatch::BandersnatchSha512Ell2 as ark_ec_vrfs::Suite>::data_to_point(vrf_input_data)
            .ok_or(())?;
    Ok(Input::from(point))
}

/// Anonymous VRF signature.
///
/// Used for tickets submission.
pub fn ring_vrf_sign(
    secret: &Secret,
    ring: &[*const Public],
    prover_idx: usize,
    ctx: &RingContext,
    vrf_input_data: &[u8],
    aux_data: &[u8],
    out_buf: &mut [u8],
) -> Result<(), ()> {
    use ark_ec_vrfs::ring::Prover as _;

    let input = vrf_input_point(vrf_input_data)?;
    let output = secret.output(input);

    // Backend currently requires the wrapped type (plain affine points)
    let pts: Vec<_> = unsafe {
        ring.iter()
            .map(|pk| {
                if pk.is_null() {
                    ctx.padding_point()
                } else {
                    (*(*pk)).0
                }
            })
            .collect()
    };

    // Proof construction
    let prover_key = ctx.prover_key(&pts);
    let prover = ctx.prover(prover_key, prover_idx);
    let proof = secret.prove(input, output, aux_data, &prover);

    // Output and Ring Proof bundled together (as per section 2.2)
    let signature = RingVrfSignature { output, proof };
    signature.serialize_compressed(out_buf).map_err(|_| ())
}

/// Non-Anonymous VRF signature.
///
/// Used for ticket claiming during block production.
/// Not used with Safrole test vectors.
pub fn ietf_vrf_sign(
    secret: &Secret,
    vrf_input_data: &[u8],
    aux_data: &[u8],
    out_buf: &mut [u8],
) -> Result<(), ()> {
    use ark_ec_vrfs::ietf::Prover as _;

    let input = vrf_input_point(vrf_input_data)?;
    let output = secret.output(input);

    let proof = secret.prove(input, output, aux_data);

    // Output and IETF Proof bundled together (as per section 2.2)
    let signature = IetfVrfSignature { output, proof };
    signature.serialize_compressed(out_buf).map_err(|_| ())
}

/// cbindgen:ignore
pub type RingCommitment = ark_ec_vrfs::ring::RingCommitment<bandersnatch::BandersnatchSha512Ell2>;

/// Anonymous VRF signature verification.
///
/// Used for tickets verification.
///
/// On success returns the VRF output hash.
pub fn ring_vrf_verify(
    ctx: &RingContext,
    commitment: &RingCommitment,
    vrf_input_data: &[u8],
    aux_data: &[u8],
    signature: &[u8],
    out_buf: &mut [u8],
) -> Result<(), ()> {
    use ark_ec_vrfs::ring::Verifier as _;

    let signature = RingVrfSignature::deserialize_compressed(signature).map_err(|_| ())?;

    let input = vrf_input_point(vrf_input_data)?;
    let output = signature.output;

    // The verifier key is reconstructed from the commitment and the constant
    // verifier key component of the SRS in order to verify some proof.
    // As an alternative we can construct the verifier key using the
    // RingContext::verifier_key() method, but is more expensive.
    // In other words, we prefer computing the commitment once, when the keyset changes.
    let verifier_key = ctx.verifier_key_from_commitment(commitment.clone());
    let verifier = ctx.verifier(verifier_key);
    if let Err(_) = Public::verify(input, output, aux_data, &signature.proof, &verifier) {
        // println!("Ring signature verification failure {:?}", e);
        return Err(());
    }
    // println!("Ring signature verified");

    // This truncated hash is the actual value used as ticket-id/score in JAM
    out_buf.copy_from_slice(&output.hash()[..32]);

    Ok(())
}

/// Non-Anonymous VRF signature verification.
///
/// Used for ticket claim verification during block import.
/// Not used with Safrole test vectors.
///
/// On success returns the VRF output hash.
pub fn ietf_vrf_verify(
    public: &Public,
    vrf_input_data: &[u8],
    aux_data: &[u8],
    signature: &[u8],
    out_buf: &mut [u8],
) -> Result<(), ()> {
    use ark_ec_vrfs::ietf::Verifier as _;

    let signature = IetfVrfSignature::deserialize_compressed(signature).map_err(|_| ())?;

    let input = vrf_input_point(vrf_input_data)?;
    let output = signature.output;

    if public
        .verify(input, output, aux_data, &signature.proof)
        .is_err()
    {
        // println!("Ietf signature verification failure");
        return Err(());
    }
    // println!("Ietf signature verified");

    // This is the actual value used as ticket-id/score
    // NOTE: as far as vrf_input_data is the same, this matches the one produced
    // using the ring-vrf (regardless of aux_data).
    out_buf.copy_from_slice(&output.hash()[..32]);

    Ok(())
}
