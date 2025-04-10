use std::{ptr, slice};

#[derive(Clone, Copy, Debug)]
pub struct Shard {
    data: *mut u8,
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

        let mut data_vec = Vec::with_capacity(data_len);
        data_vec.extend_from_slice(data_slice);

        let shard = Shard {
            data: data_vec.as_mut_ptr(),
            index,
        };

        // Prevent Vec from deallocating the memory (hand it over to the Shard)
        std::mem::forget(data_vec);

        *out = Box::into_raw(Box::new(shard));
    }

    0
}

#[no_mangle]
pub extern "C" fn shard_free(shard: *mut Shard) {
    if !shard.is_null() {
        unsafe {
            let shard = Box::from_raw(shard);
            if !shard.data.is_null() {
                drop(Box::from_raw(shard.data));
            }
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
        if shard_ref.data.is_null() {
            return 2;
        }

        *out_data = shard_ref.data;
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

    let mut original_slices = Vec::with_capacity(original_count);

    unsafe {
        for i in 0..original_count {
            let ptr = *original.add(i);
            if ptr.is_null() {
                return 2;
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
                    return 3;
                }

                unsafe {
                    ptr::copy_nonoverlapping(
                        recovery_data.as_ptr(),
                        out_ptr,
                        recovery_data.len().min(shard_size),
                    );
                }
            }
            0
        }
        Err(_) => 4,
    }
}

#[no_mangle]
pub extern "C" fn reed_solomon_recovery(
    original_count: usize,
    recovery_count: usize,
    original_shards: *const Shard,
    original_len: usize,
    recovery_shards: *const Shard,
    recovery_len: usize,
    shard_size: usize,
    out_original: *mut *mut u8,
) -> isize {
    if (original_shards.is_null() && original_len > 0)
        || (recovery_shards.is_null() && recovery_len > 0)
        || out_original.is_null()
        || original_count == 0
        || recovery_count == 0
        || shard_size == 0
    {
        return 1;
    }

    let mut original_vec = Vec::new();
    if original_len > 0 {
        let original_slice = unsafe { slice::from_raw_parts(original_shards, original_len) };
        for shard in original_slice {
            if !shard.data.is_null() {
                let data = unsafe { slice::from_raw_parts(shard.data, shard_size) };
                original_vec.push((shard.index as usize, data.to_vec()));
            }
        }
    }

    let mut recovery_vec = Vec::new();
    if recovery_len > 0 {
        let recovery_slice = unsafe { slice::from_raw_parts(recovery_shards, recovery_len) };
        for shard in recovery_slice {
            if !shard.data.is_null() {
                let data = unsafe { slice::from_raw_parts(shard.data, shard_size) };
                recovery_vec.push((shard.index as usize, data.to_vec()));
            }
        }
    }

    match reed_solomon_simd::decode(original_count, recovery_count, original_vec, recovery_vec) {
        Ok(restored) => {
            for i in 0..original_count {
                if let Some(data) = restored.get(&i) {
                    let out_ptr = unsafe { *out_original.add(i) };
                    if out_ptr.is_null() {
                        return 2;
                    }

                    unsafe {
                        ptr::copy_nonoverlapping(
                            data.as_ptr(),
                            out_ptr,
                            data.len().min(shard_size),
                        );
                    }
                }
            }
            0
        }
        Err(_) => 3,
    }
}
