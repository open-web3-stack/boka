use w3f_bls::{DoublePublicKeyScheme, Keypair, Message, SerializableToBytes, TinyBLS};

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
