use sha2::Sha256;
use w3f_bls::{
    single_pop_aggregator::SignatureAggregatorAssumingPoP, DoublePublicKey, DoublePublicKeyScheme,
    DoubleSignature, Keypair, Message, PublicKey, PublicKeyInSignatureGroup, SecretKey,
    SerializableToBytes, Signature,
};

use crate::bls::{key_pair_sign, Engine};

/// cbindgen:ignore
pub type KeyPair = Keypair<Engine>;
/// cbindgen:ignore
pub type Public = DoublePublicKey<Engine>;
/// cbindgen:ignore
pub type Secret = SecretKey<Engine>;
/// cbindgen:ignore
pub type Sig = DoubleSignature<Engine>;

#[no_mangle]
pub static BLS_PUBLICKEY_SERIALIZED_SIZE: usize = Public::SERIALIZED_BYTES_SIZE;
#[no_mangle]
pub static BLS_SIGNATURE_SERIALIZED_SIZE: usize = Sig::SERIALIZED_BYTES_SIZE;

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
    let secret = SecretKey::<Engine>::from_seed(seed_bytes);
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
    if out_len < Sig::SERIALIZED_BYTES_SIZE {
        return 2;
    }
    let key_pair: &mut Keypair<Engine> = unsafe { &mut *key_pair };
    let msg_data_slice = unsafe { std::slice::from_raw_parts(msg_data, msg_data_len) };
    let msg = Message::from(msg_data_slice);
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match key_pair_sign(key_pair, &msg, out_slice) {
        Ok(_) => 0,
        Err(_) => 3,
    }
}

#[no_mangle]
pub extern "C" fn public_new_from_bytes(
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
pub extern "C" fn public_new_from_keypair(
    key_pair: *const KeyPair,
    out_ptr: *mut *mut Public,
) -> isize {
    if key_pair.is_null() || out_ptr.is_null() {
        return 1;
    }
    let key_pair: &KeyPair = unsafe { &*key_pair };
    let public = Box::new(key_pair.into_double_public_key());
    unsafe {
        *out_ptr = Box::into_raw(public);
    }
    0
}

#[no_mangle]
pub extern "C" fn public_serialize(public: *const Public, out: *mut u8, out_len: usize) -> isize {
    if public.is_null() || out.is_null() {
        return 1;
    }
    if out_len < Public::SERIALIZED_BYTES_SIZE {
        return 2;
    }
    let public: &Public = unsafe { &*public };
    let res = public.to_bytes();
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    out_slice.copy_from_slice(&res);
    0
}

#[no_mangle]
pub extern "C" fn bls_public_free(public: *mut Public) {
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
    out: *mut bool,
) -> isize {
    if public.is_null() || signature.is_null() || msg_data.is_null() || out.is_null() {
        return 1;
    }
    let public: &Public = unsafe { &*public };
    let signature_slice = unsafe { std::slice::from_raw_parts(signature, signature_len) };
    let sig = match DoubleSignature::from_bytes(signature_slice) {
        Ok(sig) => Box::new(sig),
        Err(_) => return 2,
    };
    let msg_data_slice = unsafe { std::slice::from_raw_parts(msg_data, msg_data_len) };
    let msg = Message::from(msg_data_slice);
    let res = sig.verify(&msg, &public);
    unsafe { *out = res };
    0
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
    if len < Sig::SERIALIZED_BYTES_SIZE {
        return 2;
    }
    let bytes_slice = unsafe { std::slice::from_raw_parts(bytes, len) };
    let sig = match DoubleSignature::from_bytes(bytes_slice) {
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
    msg: *const Message,
    signatures: *const *const Sig,
    signatures_len: usize,
    publickeys: *const *const Public,
    publickeys_len: usize,
    out: *mut bool,
) -> isize {
    if signatures.is_null() || msg.is_null() || publickeys.is_null() || out.is_null() {
        return 1;
    }

    let message = unsafe { &*msg };
    let signatures_slice = unsafe { std::slice::from_raw_parts(signatures, signatures_len) };
    let publickeys_slice = unsafe { std::slice::from_raw_parts(publickeys, publickeys_len) };

    let mut aggregator = SignatureAggregatorAssumingPoP::<Engine>::new(message.clone());
    for &sig in signatures_slice {
        let sig = unsafe { &*sig };
        aggregator.add_signature(&Signature::<Engine>(sig.0));
    }
    for &public_key in publickeys_slice {
        let public_key = unsafe { &*public_key };
        aggregator.add_publickey(&PublicKey::<Engine>(public_key.1));
        aggregator.add_auxiliary_public_key(&PublicKeyInSignatureGroup::<Engine>(public_key.0));
    }

    let res = aggregator.verify_using_aggregated_auxiliary_public_keys::<Sha256>();
    unsafe { *out = res };
    0
}
