use ed25519_zebra::{Signature, SigningKey, VerificationKey, VerificationKeyBytes};

// MARK: Signing Key (Secret Key)

/// Creates a new signing key from a 32-byte seed
/// Returns 0 on success, non-zero on error
#[no_mangle]
pub extern "C" fn ed25519_signing_key_from_seed(
    seed: *const u8,
    seed_len: usize,
    out_ptr: *mut *mut SigningKey,
) -> isize {
    if seed.is_null() || out_ptr.is_null() {
        return 1;
    }
    if seed_len != 32 {
        return 2;
    }

    let seed_bytes = unsafe { std::slice::from_raw_parts(seed, seed_len) };

    // Convert slice to [u8; 32]
    let seed_array: [u8; 32] = match seed_bytes.try_into() {
        Ok(arr) => arr,
        Err(_) => return 2,
    };

    let signing_key = Box::new(SigningKey::from(seed_array));
    unsafe {
        *out_ptr = Box::into_raw(signing_key);
    }
    0
}

/// Frees a signing key
#[no_mangle]
pub extern "C" fn ed25519_signing_key_free(signing_key: *mut SigningKey) {
    if !signing_key.is_null() {
        unsafe {
            drop(Box::from_raw(signing_key));
        }
    }
}

/// Exports signing key to 32 bytes (the seed)
/// Returns 0 on success, non-zero on error
#[no_mangle]
pub extern "C" fn ed25519_signing_key_to_bytes(
    signing_key: *const SigningKey,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if signing_key.is_null() || out.is_null() {
        return 1;
    }
    if out_len != 32 {
        return 2;
    }

    let signing_key = unsafe { &*signing_key };
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    let bytes: [u8; 32] = signing_key.to_bytes();
    out_slice.copy_from_slice(&bytes);
    0
}

/// Signs a message with the signing key
/// Returns 0 on success, non-zero on error
#[no_mangle]
pub extern "C" fn ed25519_sign(
    signing_key: *const SigningKey,
    message: *const u8,
    message_len: usize,
    signature_out: *mut u8,
    signature_out_len: usize,
) -> isize {
    if signing_key.is_null() || message.is_null() || signature_out.is_null() {
        return 1;
    }
    if signature_out_len != 64 {
        return 2;
    }

    let signing_key = unsafe { &*signing_key };
    let message_slice = unsafe { std::slice::from_raw_parts(message, message_len) };
    let signature_slice =
        unsafe { std::slice::from_raw_parts_mut(signature_out, signature_out_len) };

    let signature = signing_key.sign(message_slice);
    signature_slice.copy_from_slice(&<[u8; 64]>::from(signature));
    0
}

// MARK: Verification Key (Public Key)

/// Creates a verification key from a signing key
/// Returns 0 on success, non-zero on error
#[no_mangle]
pub extern "C" fn ed25519_verification_key_from_signing_key(
    signing_key: *const SigningKey,
    out_ptr: *mut *mut VerificationKey,
) -> isize {
    if signing_key.is_null() || out_ptr.is_null() {
        return 1;
    }

    let signing_key = unsafe { &*signing_key };
    let verification_key = Box::new(VerificationKey::from(signing_key));
    unsafe {
        *out_ptr = Box::into_raw(verification_key);
    }
    0
}

/// Creates a verification key from 32 bytes
/// Returns 0 on success, non-zero on error
#[no_mangle]
pub extern "C" fn ed25519_verification_key_from_bytes(
    bytes: *const u8,
    bytes_len: usize,
    out_ptr: *mut *mut VerificationKey,
) -> isize {
    if bytes.is_null() || out_ptr.is_null() {
        return 1;
    }
    if bytes_len != 32 {
        return 2;
    }

    let bytes_slice = unsafe { std::slice::from_raw_parts(bytes, bytes_len) };

    // Convert slice to [u8; 32]
    let bytes_array: [u8; 32] = match bytes_slice.try_into() {
        Ok(arr) => arr,
        Err(_) => return 2,
    };

    let vk_bytes = VerificationKeyBytes::from(bytes_array);
    match VerificationKey::try_from(vk_bytes) {
        Ok(vk) => {
            let verification_key = Box::new(vk);
            unsafe {
                *out_ptr = Box::into_raw(verification_key);
            }
            0
        }
        Err(_) => 3,
    }
}

/// Exports verification key to 32 bytes
/// Returns 0 on success, non-zero on error
#[no_mangle]
pub extern "C" fn ed25519_verification_key_to_bytes(
    verification_key: *const VerificationKey,
    out: *mut u8,
    out_len: usize,
) -> isize {
    if verification_key.is_null() || out.is_null() {
        return 1;
    }
    if out_len != 32 {
        return 2;
    }

    let verification_key = unsafe { &*verification_key };
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    let bytes: VerificationKeyBytes = (*verification_key).into();
    out_slice.copy_from_slice(&<[u8; 32]>::from(bytes));
    0
}

/// Frees a verification key
#[no_mangle]
pub extern "C" fn ed25519_verification_key_free(verification_key: *mut VerificationKey) {
    if !verification_key.is_null() {
        unsafe {
            drop(Box::from_raw(verification_key));
        }
    }
}

// MARK: Signature Verification

/// Verifies a signature using ZIP 215 rules (consensus-critical)
/// Returns 0 on success, non-zero on error
/// Sets `out` to true if signature is valid, false if invalid
#[no_mangle]
pub extern "C" fn ed25519_verify(
    verification_key: *const VerificationKey,
    signature: *const u8,
    signature_len: usize,
    message: *const u8,
    message_len: usize,
    out: *mut bool,
) -> isize {
    if verification_key.is_null() || signature.is_null() || message.is_null() || out.is_null() {
        return 1;
    }
    if signature_len != 64 {
        return 2;
    }

    let verification_key = unsafe { &*verification_key };
    let signature_slice = unsafe { std::slice::from_raw_parts(signature, signature_len) };
    let message_slice = unsafe { std::slice::from_raw_parts(message, message_len) };

    // Convert slice to [u8; 64]
    let signature_array: [u8; 64] = match signature_slice.try_into() {
        Ok(arr) => arr,
        Err(_) => return 2,
    };
    let sig = Signature::from(signature_array);

    let is_valid = verification_key.verify(&sig, message_slice).is_ok();
    unsafe { *out = is_valid };
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sign_and_verify() {
        let seed = [42u8; 32];
        let message = b"test message";

        // Create signing key
        let mut signing_key_ptr: *mut SigningKey = std::ptr::null_mut();
        let result = ed25519_signing_key_from_seed(
            seed.as_ptr(),
            seed.len(),
            &mut signing_key_ptr as *mut *mut SigningKey,
        );
        assert_eq!(result, 0);
        assert!(!signing_key_ptr.is_null());

        // Create verification key
        let mut verification_key_ptr: *mut VerificationKey = std::ptr::null_mut();
        let result = ed25519_verification_key_from_signing_key(
            signing_key_ptr,
            &mut verification_key_ptr as *mut *mut VerificationKey,
        );
        assert_eq!(result, 0);
        assert!(!verification_key_ptr.is_null());

        // Sign message
        let mut signature = [0u8; 64];
        let result = ed25519_sign(
            signing_key_ptr,
            message.as_ptr(),
            message.len(),
            signature.as_mut_ptr(),
            signature.len(),
        );
        assert_eq!(result, 0);

        // Verify signature
        let mut is_valid = false;
        let result = ed25519_verify(
            verification_key_ptr,
            signature.as_ptr(),
            signature.len(),
            message.as_ptr(),
            message.len(),
            &mut is_valid as *mut bool,
        );
        assert_eq!(result, 0);
        assert!(is_valid);

        // Cleanup
        ed25519_verification_key_free(verification_key_ptr);
        ed25519_signing_key_free(signing_key_ptr);
    }

    #[test]
    fn test_invalid_signature() {
        let seed = [42u8; 32];
        let message = b"test message";
        let wrong_message = b"wrong message";

        let mut signing_key_ptr: *mut SigningKey = std::ptr::null_mut();
        ed25519_signing_key_from_seed(
            seed.as_ptr(),
            seed.len(),
            &mut signing_key_ptr as *mut *mut SigningKey,
        );

        let mut verification_key_ptr: *mut VerificationKey = std::ptr::null_mut();
        ed25519_verification_key_from_signing_key(
            signing_key_ptr,
            &mut verification_key_ptr as *mut *mut VerificationKey,
        );

        let mut signature = [0u8; 64];
        ed25519_sign(
            signing_key_ptr,
            message.as_ptr(),
            message.len(),
            signature.as_mut_ptr(),
            signature.len(),
        );

        // Verify with wrong message should fail
        let mut is_valid = false;
        let result = ed25519_verify(
            verification_key_ptr,
            signature.as_ptr(),
            signature.len(),
            wrong_message.as_ptr(),
            wrong_message.len(),
            &mut is_valid as *mut bool,
        );
        assert_eq!(result, 0);
        assert!(!is_valid);

        ed25519_verification_key_free(verification_key_ptr);
        ed25519_signing_key_free(signing_key_ptr);
    }
}
