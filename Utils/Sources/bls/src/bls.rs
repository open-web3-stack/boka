use sha2::Sha256;
use w3f_bls::{
    single_pop_aggregator::SignatureAggregatorAssumingPoP, DoublePublicKey, DoublePublicKeyScheme,
    DoubleSignature, Keypair, Message, SerializableToBytes, TinyBLS,
};

pub type Engine = TinyBLS<ark_bls12_381::Bls12_381, ark_bls12_381::Config>;

pub fn key_pair_sign(
    key_pair: &mut Keypair<Engine>,
    msg: &Message,
    out_buf: &mut [u8],
) -> Result<(), ()> {
    let sig = DoublePublicKeyScheme::sign(key_pair, msg);
    let sig_bytes = sig.to_bytes();
    out_buf.copy_from_slice(&sig_bytes);
    Ok(())
}

pub fn signature_verify(
    sig: &DoubleSignature<Engine>,
    msg: &Message,
    pub_key: &DoublePublicKey<Engine>,
    out_buf: &mut [u8],
) -> Result<(), ()> {
    let res = sig.verify(msg, pub_key);
    out_buf[0] = if res { 1 } else { 0 };
    Ok(())
}

pub fn aggregated_verify(
    aggregator: SignatureAggregatorAssumingPoP<Engine>,
    out_buf: &mut [u8],
) -> Result<(), ()> {
    // TODO: check using `verify` or `verify_using_aggregated_auxiliary_public_keys`
    let res = aggregator.verify_using_aggregated_auxiliary_public_keys::<Sha256>();
    out_buf[0] = if res { 1 } else { 0 };
    Ok(())
}
