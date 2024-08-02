// Code copied and modified based on: https://github.com/davxy/bandersnatch-vrfs-spec/blob/470d836ae5c8ee9509892f90cf3eebf21ddf55c2/example/src/main.rs
// Changes: made RING_SIZE configurable, add attributes for cbindgen and ffi, remove extra log

use ark_ec_vrfs::suites::bandersnatch::edwards as bandersnatch;
use ark_ec_vrfs::{prelude::ark_serialize, suites::bandersnatch::edwards::RingContext};
use bandersnatch::{IetfProof, Input, Output, Public, RingProof, Secret};

use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};

const RING_SIZE_TINY: usize = 6;
const RING_SIZE_FULL: usize = 1023;

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

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub enum RingSize {
    Tiny,
    Full,
}

fn ring_context_tiny() -> &'static RingContext {
    use std::sync::OnceLock;
    static RING_CTX: OnceLock<RingContext> = OnceLock::new();
    RING_CTX.get_or_init(|| {
        use bandersnatch::PcsParams;
        let buf: &'static [u8] = include_bytes!("../data/zcash-srs-2-11-uncompressed.bin");
        let pcs_params = PcsParams::deserialize_uncompressed_unchecked(&mut &buf[..]).unwrap();
        RingContext::from_srs(RING_SIZE_TINY, pcs_params).unwrap()
    })
}

fn ring_context_full() -> &'static RingContext {
    use std::sync::OnceLock;
    static RING_CTX: OnceLock<RingContext> = OnceLock::new();
    RING_CTX.get_or_init(|| {
        use bandersnatch::PcsParams;
        let buf: &'static [u8] = include_bytes!("../data/zcash-srs-2-11-uncompressed.bin");
        let pcs_params = PcsParams::deserialize_uncompressed_unchecked(&mut &buf[..]).unwrap();
        RingContext::from_srs(RING_SIZE_FULL, pcs_params).unwrap()
    })
}

// "Static" ring context data
fn ring_context(size: RingSize) -> &'static RingContext {
    match size {
        RingSize::Tiny => ring_context_tiny(),
        RingSize::Full => ring_context_full(),
    }
}

// Construct VRF Input Point from arbitrary data (section 1.2)
fn vrf_input_point(vrf_input_data: &[u8]) -> Input {
    let point =
        <bandersnatch::BandersnatchSha512Ell2 as ark_ec_vrfs::Suite>::data_to_point(vrf_input_data)
            .unwrap();
    Input::from(point)
}

// Prover actor.
pub struct Prover {
    pub prover_idx: usize,
    pub secret: Secret,
    pub ring: Vec<Public>,
    pub ring_size: RingSize,
}

impl Prover {
    pub fn new(ring: Vec<Public>, prover_idx: usize, ring_size: RingSize) -> Self {
        Self {
            prover_idx,
            secret: Secret::from_seed(&prover_idx.to_le_bytes()),
            ring,
            ring_size,
        }
    }

    /// Anonymous VRF signature.
    ///
    /// Used for tickets submission.
    pub fn ring_vrf_sign(&self, vrf_input_data: &[u8], aux_data: &[u8]) -> Vec<u8> {
        use ark_ec_vrfs::ring::Prover as _;

        let input = vrf_input_point(vrf_input_data);
        let output = self.secret.output(input);

        // Backend currently requires the wrapped type (plain affine points)
        let pts: Vec<_> = self.ring.iter().map(|pk| pk.0).collect();

        // Proof construction
        let ring_ctx = ring_context(self.ring_size);
        let prover_key = ring_ctx.prover_key(&pts);
        let prover = ring_ctx.prover(prover_key, self.prover_idx);
        let proof = self.secret.prove(input, output, aux_data, &prover);

        // Output and Ring Proof bundled together (as per section 2.2)
        let signature = RingVrfSignature { output, proof };
        let mut buf = Vec::new();
        signature.serialize_compressed(&mut buf).unwrap();
        buf
    }

    /// Non-Anonymous VRF signature.
    ///
    /// Used for ticket claiming during block production.
    /// Not used with Safrole test vectors.
    pub fn ietf_vrf_sign(&self, vrf_input_data: &[u8], aux_data: &[u8]) -> Vec<u8> {
        use ark_ec_vrfs::ietf::Prover as _;

        let input = vrf_input_point(vrf_input_data);
        let output = self.secret.output(input);

        let proof = self.secret.prove(input, output, aux_data);

        // Output and IETF Proof bundled together (as per section 2.2)
        let signature = IetfVrfSignature { output, proof };
        let mut buf = Vec::new();
        signature.serialize_compressed(&mut buf).unwrap();
        buf
    }
}

/// cbindgen:ignore
pub type RingCommitment = ark_ec_vrfs::ring::RingCommitment<bandersnatch::BandersnatchSha512Ell2>;

// Verifier actor.
pub struct Verifier {
    pub commitment: RingCommitment,
    pub ring: Vec<Public>,
    pub ring_size: RingSize,
}

impl Verifier {
    pub fn new(ring: Vec<Public>, ring_size: RingSize) -> Self {
        // Backend currently requires the wrapped type (plain affine points)
        let pts: Vec<_> = ring.iter().map(|pk| pk.0).collect();
        let verifier_key = ring_context(ring_size).verifier_key(&pts);
        let commitment = verifier_key.commitment();
        Self {
            ring,
            commitment,
            ring_size,
        }
    }

    /// Anonymous VRF signature verification.
    ///
    /// Used for tickets verification.
    ///
    /// On success returns the VRF output hash.
    pub fn ring_vrf_verify(
        &self,
        vrf_input_data: &[u8],
        aux_data: &[u8],
        signature: &[u8],
    ) -> Result<[u8; 32], ()> {
        use ark_ec_vrfs::ring::Verifier as _;

        let signature = RingVrfSignature::deserialize_compressed(signature).unwrap();

        let input = vrf_input_point(vrf_input_data);
        let output = signature.output;

        let ring_ctx = ring_context(self.ring_size);

        // The verifier key is reconstructed from the commitment and the constant
        // verifier key component of the SRS in order to verify some proof.
        // As an alternative we can construct the verifier key using the
        // RingContext::verifier_key() method, but is more expensive.
        // In other words, we prefer computing the commitment once, when the keyset changes.
        let verifier_key = ring_ctx.verifier_key_from_commitment(self.commitment.clone());
        let verifier = ring_ctx.verifier(verifier_key);
        if Public::verify(input, output, aux_data, &signature.proof, &verifier).is_err() {
            // println!("Ring signature verification failure");
            return Err(());
        }
        // println!("Ring signature verified");

        // This truncated hash is the actual value used as ticket-id/score in JAM
        let vrf_output_hash: [u8; 32] = output.hash()[..32].try_into().unwrap();
        // println!(" vrf-output-hash: {}", hex::encode(vrf_output_hash));
        Ok(vrf_output_hash)
    }

    /// Non-Anonymous VRF signature verification.
    ///
    /// Used for ticket claim verification during block import.
    /// Not used with Safrole test vectors.
    ///
    /// On success returns the VRF output hash.
    pub fn ietf_vrf_verify(
        &self,
        vrf_input_data: &[u8],
        aux_data: &[u8],
        signature: &[u8],
        signer_key_index: usize,
    ) -> Result<[u8; 32], ()> {
        use ark_ec_vrfs::ietf::Verifier as _;

        let signature = IetfVrfSignature::deserialize_compressed(signature).unwrap();

        let input = vrf_input_point(vrf_input_data);
        let output = signature.output;

        let public = &self.ring[signer_key_index];
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
        let vrf_output_hash: [u8; 32] = output.hash()[..32].try_into().unwrap();
        // println!(" vrf-output-hash: {}", hex::encode(vrf_output_hash));
        Ok(vrf_output_hash)
    }
}
