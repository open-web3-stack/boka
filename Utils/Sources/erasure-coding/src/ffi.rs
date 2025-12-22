use std::{ptr, slice};

#[derive(Clone, Debug)]
pub struct Shard {
    data: Vec<u8>,
    index: u32,
}

#[no_mangle]
pub extern "C" fn shard_new(
    data: *const u8,
    data_len: usize,
    index: u32,
    out: *mut *mut Shard,
) -> isize {
    if data.is_null() || out.is_null() || data_len == 0 {
        return 1;
    }

    unsafe {
        let data_slice = slice::from_raw_parts(data, data_len);

        let data_vec = data_slice.to_vec();

        let shard = Shard {
            data: data_vec,
            index,
        };

        *out = Box::into_raw(Box::new(shard));
    }

    0
}

#[no_mangle]
pub extern "C" fn shard_free(shard: *mut Shard) {
    if !shard.is_null() {
        unsafe {
            drop(Box::from_raw(shard));
        }
    }
}

#[no_mangle]
pub extern "C" fn shard_get_data(shard: *const Shard, out_data: *mut *const u8) -> isize {
    if shard.is_null() || out_data.is_null() {
        return 1;
    }

    unsafe {
        let shard_ref = &*shard;
        *out_data = shard_ref.data.as_ptr();
    }

    0
}

#[no_mangle]
pub extern "C" fn shard_get_index(shard: *const Shard, out_index: *mut u32) -> isize {
    if shard.is_null() || out_index.is_null() {
        return 1;
    }

    unsafe {
        let shard_ref = &*shard;
        *out_index = shard_ref.index;
    }

    0
}

#[no_mangle]
pub extern "C" fn reed_solomon_encode(
    original: *const *const u8,
    original_count: usize,
    recovery_count: usize,
    shard_size: usize,
    out_recovery: *mut *mut u8,
) -> isize {
    if original.is_null()
        || out_recovery.is_null()
        || original_count == 0
        || recovery_count == 0
        || shard_size == 0
    {
        return 1;
    }

    if shard_size % 2 != 0 {
        return 2;
    }

    let mut original_slices = Vec::with_capacity(original_count);

    unsafe {
        for i in 0..original_count {
            let ptr = *original.add(i);
            if ptr.is_null() {
                return 3;
            }
            original_slices.push(slice::from_raw_parts(ptr, shard_size));
        }
    }

    match reed_solomon_simd::encode(original_count, recovery_count, original_slices) {
        Ok(recovery_vecs) => {
            for (i, recovery_data) in recovery_vecs.iter().enumerate() {
                if i >= recovery_count {
                    break;
                }

                let out_ptr = unsafe { *out_recovery.add(i) };
                if out_ptr.is_null() {
                    return 4;
                }

                unsafe {
                    ptr::copy_nonoverlapping(recovery_data.as_ptr(), out_ptr, recovery_data.len());
                }
            }
            0
        }
        Err(e) => {
            println!("FFI: Error in reed_solomon_encode, error: {:?}", e);
            4
        }
    }
}

#[no_mangle]
pub extern "C" fn reed_solomon_recovery(
    original_count: usize,
    recovery_count: usize,
    original_shards: *const *const Shard,
    original_len: usize,
    recovery_shards: *const *const Shard,
    recovery_len: usize,
    shard_size: usize,
    out_original: *mut *mut u8,
) -> isize {
    if out_original.is_null() || original_count == 0 || recovery_count == 0 || shard_size == 0 {
        return 1;
    }

    if shard_size % 2 != 0 {
        return 2;
    }

    let mut original_vec = Vec::new();
    if original_len > 0 && !original_shards.is_null() {
        for i in 0..original_len {
            let shard_ptr = unsafe { *original_shards.add(i) };
            let shard = unsafe { &*shard_ptr };

            let data = shard.data.as_slice();
            original_vec.push((shard.index as usize, data.to_vec()));
        }
    }

    let mut recovery_vec = Vec::new();
    if recovery_len > 0 && !recovery_shards.is_null() {
        for i in 0..recovery_len {
            let shard_ptr = unsafe { *recovery_shards.add(i) };
            let shard = unsafe { &*shard_ptr };

            let data = shard.data.as_slice();
            recovery_vec.push((shard.index as usize, data.to_vec()));
        }
    }

    match reed_solomon_simd::decode(original_count, recovery_count, original_vec, recovery_vec) {
        Ok(restored) => {
            for i in 0..original_count {
                if let Some(data) = restored.get(&i) {
                    let out_ptr = unsafe { *out_original.add(i) };
                    if out_ptr.is_null() {
                        return 3;
                    }

                    unsafe {
                        ptr::copy_nonoverlapping(data.as_ptr(), out_ptr, data.len());
                    }
                }
            }
            0
        }
        Err(e) => {
            println!("FFI: Error in reed_solomon_recovery, error: {:?}", e);
            4
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_shard(data: &[u8], index: u32) -> *mut Shard {
        let mut out = std::ptr::null_mut();
        let ret = shard_new(data.as_ptr(), data.len(), index, &mut out);
        assert_eq!(ret, 0, "shard_new failed with code {ret}");
        out
    }

    #[test]
    fn shard_roundtrip() {
        let data = [1u8, 2, 3, 4];
        let shard_ptr = make_shard(&data, 7);
        let mut out_data = std::ptr::null();
        let mut out_index: u32 = 0;
        unsafe {
            assert_eq!(shard_get_data(shard_ptr, &mut out_data), 0);
            assert_eq!(shard_get_index(shard_ptr, &mut out_index), 0);
            assert_eq!(out_index, 7);
            let slice = std::slice::from_raw_parts(out_data, data.len());
            assert_eq!(slice, data);
            shard_free(shard_ptr);
        }
    }

    #[test]
    fn debug_original_reed_solomon_encode_recover() {
        let original_count = 2;
        let recovery_count = 5;

        let original_data = vec![vec![0u8, 15u8], vec![30u8, 45u8]];

        println!("Original shards:");
        for (i, shard) in original_data.iter().enumerate() {
            println!("Shard {}: {:?}", i, shard);
        }

        let original_slices: Vec<&[u8]> = original_data.iter().map(|v| v.as_slice()).collect();

        let recovery_result =
            reed_solomon_simd::encode(original_count, recovery_count, original_slices);
        assert!(recovery_result.is_ok());

        let recovery_data = recovery_result.unwrap();

        println!("Recovery shards from reed_solomon_simd:");
        for (i, shard) in recovery_data.iter().enumerate() {
            println!("Shard {}: {:?}", i, shard);
        }

        let mut recovery_shards = Vec::new();
        for i in (recovery_count - original_count)..recovery_count {
            recovery_shards.push((i, recovery_data[i].clone()));
        }

        println!("Recovery shards used for decode:");
        for (i, (idx, shard)) in recovery_shards.iter().enumerate() {
            println!("Shard {} (index {}): {:?}", i, idx, shard);
        }

        let restored_result = reed_solomon_simd::decode(
            original_count,
            recovery_count,
            Vec::<(usize, Vec<u8>)>::new(),
            recovery_shards,
        );

        assert!(restored_result.is_ok());
        let restored = restored_result.unwrap();

        println!("Restored original shards:");
        for i in 0..original_count {
            if let Some(data) = restored.get(&i) {
                println!("Shard {}: {:?}", i, data);
                assert_eq!(*data, original_data[i]);
            }
        }
    }

    #[test]
    fn ffi_encode_recover_parity_only_roundtrip() {
        let original_count = 2;
        let parity_count = 3; // matches Swift usage (recoveryCount - originalCount)
        let shard_size = 4usize;

        let original_data = vec![vec![1u8, 2, 3, 4], vec![5u8, 6, 7, 8]];

        let original_ptrs: Vec<*const u8> = original_data.iter().map(|v| v.as_ptr()).collect();
        let mut recovery_buffers: Vec<Vec<u8>> = vec![vec![0u8; shard_size]; parity_count];
        let mut recovery_ptrs: Vec<*mut u8> = recovery_buffers
            .iter_mut()
            .map(|v| v.as_mut_ptr())
            .collect();

        let ret = reed_solomon_encode(
            original_ptrs.as_ptr(),
            original_count,
            parity_count,
            shard_size,
            recovery_ptrs.as_mut_ptr(),
        );
        assert_eq!(ret, 0, "reed_solomon_encode failed with {ret}");

        let mut recovery_shards: Vec<*mut Shard> = Vec::new();
        for (i, buf) in recovery_buffers.iter().enumerate() {
            let shard = make_shard(buf, i as u32);
            recovery_shards.push(shard);
        }
        let recovery_shards_const: Vec<*const Shard> =
            recovery_shards.iter().map(|&p| p as *const Shard).collect();

        // Output buffers
        let mut out_original: Vec<Vec<u8>> = vec![vec![0u8; shard_size]; original_count];
        let mut out_ptrs: Vec<*mut u8> = out_original.iter_mut().map(|v| v.as_mut_ptr()).collect();

        let ret = reed_solomon_recovery(
            original_count,
            parity_count,
            std::ptr::null(),
            0,
            recovery_shards_const.as_ptr(),
            recovery_shards_const.len(),
            shard_size,
            out_ptrs.as_mut_ptr(),
        );
        assert_eq!(ret, 0, "reed_solomon_recovery failed with {ret}");

        assert_eq!(out_original, original_data);

        // free shards
        for shard in recovery_shards {
            shard_free(shard);
        }
    }
}
