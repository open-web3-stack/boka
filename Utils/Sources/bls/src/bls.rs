use w3f_bls::{
    distinct::DistinctMessages, Keypair, Message, PublicKey, SerializableToBytes, Signature,
    Signed, ZBLS,
};

pub fn key_pair_sign(
    key_pair: &mut Keypair<ZBLS>,
    msg: &Message,
    out_buf: &mut [u8],
) -> Result<(), ()> {
    let sig = key_pair.sign(msg);
    let sig_bytes = sig.to_bytes();
    out_buf.copy_from_slice(&sig_bytes);
    Ok(())
}

pub fn signature_verify(
    sig: &Signature<ZBLS>,
    msg: &Message,
    pub_key: &PublicKey<ZBLS>,
    out_buf: &mut [u8],
) -> Result<(), ()> {
    let res = sig.verify(msg, pub_key);
    out_buf[0] = if res { 1 } else { 0 };
    Ok(())
}

pub fn aggregated_verify(dms: &DistinctMessages<ZBLS>, out_buf: &mut [u8]) -> Result<(), ()> {
    let res = dms.verify();
    out_buf[0] = if res { 1 } else { 0 };
    Ok(())
}
