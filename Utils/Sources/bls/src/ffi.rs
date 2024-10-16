use w3f_bls::{
    distinct::DistinctMessages, Keypair, Message, PublicKey, SecretKey, SerializableToBytes,
    Signature, Signed, ZBLS,
};

use crate::bls::{aggregated_verify, key_pair_sign, signature_verify};

/// cbindgen:ignore
pub type KeyPair = Keypair<ZBLS>;
/// cbindgen:ignore
pub type Public = PublicKey<ZBLS>;
/// cbindgen:ignore
pub type Secret = SecretKey<ZBLS>;
/// cbindgen:ignore
pub type Sig = Signature<ZBLS>;

#[no_mangle]
pub extern "C" fn keypair_new(
    seed: *const u8,
    seed_len: usize,
    out_ptr: *mut *mut KeyPair,
) -> isize {
    if seed.is_null() || out_ptr.is_null() {
        return 1;
    }
    let seed_bytes = unsafe { std::slice::from_raw_parts(seed, seed_len) };
    let secret = SecretKey::<ZBLS>::from_seed(seed_bytes);
    let keypair = Box::new(Keypair {
        public: secret.into_public(),
        secret,
    });
    unsafe {
        *out_ptr = Box::into_raw(keypair);
    }
    0
}

#[no_mangle]
pub extern "C" fn keypair_free(keypair: *mut KeyPair) {
    if !keypair.is_null() {
        unsafe {
            drop(Box::from_raw(keypair));
        }
    }
}

#[no_mangle]
pub extern "C" fn keypair_sign(
    key_pair: *mut KeyPair,
    msg_data: *const u8,
    msg_data_len: usize,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if key_pair.is_null() || msg_data.is_null() || out.is_null() {
        return 1;
    }
    if out_len < 96 {
        return 2;
    }
    let key_pair: &mut Keypair<ZBLS> = unsafe { &mut *key_pair };
    let msg_data_slice = unsafe { std::slice::from_raw_parts(msg_data, msg_data_len) };
    let msg = Message::from(msg_data_slice);
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match key_pair_sign(key_pair, &msg, out_slice) {
        Ok(_) => 0,
        Err(_) => 3,
    }
}

#[no_mangle]
pub extern "C" fn public_new_from_keypair(
    key_pair: *const KeyPair,
    out_ptr: *mut *mut Public,
) -> isize {
    if key_pair.is_null() || out_ptr.is_null() {
        return 1;
    }
    let key_pair: &KeyPair = unsafe { &*key_pair };
    let public = Box::new(key_pair.public);
    unsafe {
        *out_ptr = Box::into_raw(public);
    }
    0
}

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
    let public = match Public::from_bytes(data_slice) {
        Ok(public) => Box::new(public),
        Err(_) => return 2,
    };
    unsafe { *out_ptr = Box::into_raw(public) };
    0
}

#[no_mangle]
pub extern "C" fn public_serialize(public: *const Public, out: *mut u8, out_len: usize) -> isize {
    if public.is_null() || out.is_null() {
        return 1;
    }
    if out_len < 144 {
        return 2;
    }
    let public: &Public = unsafe { &*public };
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    out_slice.copy_from_slice(&public.to_bytes());
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
pub extern "C" fn public_verify(
    public: *const Public,
    signature: *const u8,
    signature_len: usize,
    msg_data: *const u8,
    msg_data_len: usize,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if public.is_null() || signature.is_null() || msg_data.is_null() || out.is_null() {
        return 1;
    }
    let public: &Public = unsafe { &*public };
    let signature_slice = unsafe { std::slice::from_raw_parts(signature, signature_len) };
    let sig = match Signature::from_bytes(signature_slice) {
        Ok(sig) => Box::new(sig),
        Err(_) => return 2,
    };
    let msg_data_slice = unsafe { std::slice::from_raw_parts(msg_data, msg_data_len) };
    let msg = Message::from(msg_data_slice);
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match signature_verify(&sig, &msg, &public, out_slice) {
        Ok(_) => 0,
        Err(_) => 3,
    }
}

#[no_mangle]
pub extern "C" fn message_new_from_bytes(
    msg_data: *const u8,
    msg_data_len: usize,
    out_ptr: *mut *mut Message,
) -> isize {
    if msg_data.is_null() || out_ptr.is_null() {
        return 1;
    }
    if msg_data_len < 96 {
        return 2;
    }
    let msg_data_slice = unsafe { std::slice::from_raw_parts(msg_data, msg_data_len) };
    let msg = Message::from(msg_data_slice);
    unsafe { *out_ptr = Box::into_raw(Box::new(msg)) };
    0
}

#[no_mangle]
pub extern "C" fn message_free(msg: *mut Message) {
    if !msg.is_null() {
        unsafe {
            drop(Box::from_raw(msg));
        }
    }
}

#[no_mangle]
pub extern "C" fn signature_new_from_bytes(
    bytes: *const u8,
    len: usize,
    out_ptr: *mut *mut Sig,
) -> isize {
    if bytes.is_null() || out_ptr.is_null() {
        return 1;
    }
    if len < 96 {
        return 2;
    }
    let bytes_slice = unsafe { std::slice::from_raw_parts(bytes, len) };
    let sig = match Signature::from_bytes(bytes_slice) {
        Ok(sig) => Box::new(sig),
        Err(_) => return 3,
    };
    unsafe { *out_ptr = Box::into_raw(sig) };
    0
}

#[no_mangle]
pub extern "C" fn signature_free(sigs: *mut Sig) {
    if !sigs.is_null() {
        unsafe {
            drop(Box::from_raw(sigs));
        }
    }
}

#[no_mangle]
pub extern "C" fn aggeregated_verify(
    signatures: *const *const Sig,
    signatures_len: usize,
    msgs: *const *const Message,
    msgs_len: usize,
    publickeys: *const *const Public,
    publickeys_len: usize,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if signatures.is_null() || msgs.is_null() || publickeys.is_null() || out.is_null() {
        return 1;
    }
    if out_len < 1 {
        return 2;
    }
    let signatures_slice = unsafe { std::slice::from_raw_parts(signatures, signatures_len) };
    let msgs_slice = unsafe { std::slice::from_raw_parts(msgs, msgs_len) };
    let publickeys_slice = unsafe { std::slice::from_raw_parts(publickeys, publickeys_len) };

    let mut dms = DistinctMessages::<ZBLS>::new();
    for &sig_ptr in signatures_slice.iter() {
        let sig = unsafe { &*sig_ptr };
        dms.add_signature(sig);
    }
    let aggregated_signature = <&DistinctMessages<ZBLS> as Signed>::signature(&&dms);

    let mut dms = DistinctMessages::<ZBLS>::new();
    for (&message_ptr, &publickey_ptr) in msgs_slice.iter().zip(publickeys_slice.iter()) {
        let message = unsafe { (*message_ptr).clone() };
        let publickey = unsafe { *publickey_ptr };
        dms = match dms.add_message_n_publickey(message, publickey) {
            Ok(dms) => dms,
            Err(_) => return 3, // AttackViaDuplicateMessages
        }
    }
    dms.add_signature(&aggregated_signature);
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match aggregated_verify(&dms, out_slice) {
        Ok(_) => 0,
        Err(_) => 4,
    }
}

#[no_mangle]
pub extern "C" fn aggregate_signatures(
    sigs_raw: *const *const Sig,
    sigs_len: usize,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if sigs_raw.is_null() || out.is_null() {
        return 1;
    }
    if out_len < 96 {
        return 2;
    }

    let sigs_slice = unsafe { std::slice::from_raw_parts(sigs_raw, sigs_len) };
    let mut dms = DistinctMessages::<ZBLS>::new();
    for &sig_ptr in sigs_slice.iter() {
        let sig = unsafe { &*sig_ptr };
        dms.add_signature(sig);
    }
    let signature = <&DistinctMessages<ZBLS> as Signed>::signature(&&dms);

    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    out_slice.copy_from_slice(&signature.to_bytes());
    0
}
