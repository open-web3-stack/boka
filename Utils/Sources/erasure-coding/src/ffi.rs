use erasure_coding::{
    ChunkIndex, Segment, SubShardDecoder, SubShardEncoder, SEGMENT_SIZE, TOTAL_SHARDS,
};
use std::slice;

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct CSegment {
    data: *mut u8, // Pointer to the data, length is SEGMENT_SIZE
    index: u32,
}

impl From<Segment> for CSegment {
    fn from(segment: Segment) -> Self {
        let mut vec_data = Vec::from(*segment.data);

        let c_segment = CSegment {
            data: vec_data.as_mut_ptr(),
            index: segment.index,
        };

        // prevent Rust from freeing the Vec while CSegment is in use
        std::mem::forget(vec_data);

        c_segment
    }
}

impl From<CSegment> for Segment {
    fn from(c_segment: CSegment) -> Self {
        let vec_data = unsafe { Vec::from_raw_parts(c_segment.data, SEGMENT_SIZE, SEGMENT_SIZE) };

        Segment {
            data: Box::new(vec_data.try_into().unwrap()),
            index: c_segment.index,
        }
    }
}

/// Initializes a new SubShardEncoder.
#[no_mangle]
pub extern "C" fn subshard_encoder_new() -> *mut SubShardEncoder {
    Box::into_raw(Box::new(SubShardEncoder::new().unwrap()))
}

/// Frees the SubShardEncoder.
#[no_mangle]
pub extern "C" fn subshard_encoder_free(encoder: *mut SubShardEncoder) {
    if !encoder.is_null() {
        unsafe { drop(Box::from_raw(encoder)) };
    }
}

/// Constructs erasure-coded chunks from segments.
///
/// out_chunks is N chunks: `Vec<[[u8; 12]; TOTAL_SHARDS]>`
/// out_len is N * TOTAL_SHARDS
#[no_mangle]
pub extern "C" fn subshard_encoder_construct(
    encoder: *mut SubShardEncoder,
    segments: *const CSegment,
    num_segments: usize,
    success: *mut bool,
    out_chunks: *mut *mut *mut [u8; 12],
    out_len: *mut usize,
) {
    if encoder.is_null() || segments.is_null() || out_chunks.is_null() || out_len.is_null() {
        unsafe { *success = false };
        return;
    }

    let encoder = unsafe { &mut *encoder };
    let segments_vec: Vec<Segment> = unsafe {
        slice::from_raw_parts(segments, num_segments)
            .iter()
            .map(|segment| Segment::from(*segment))
            .collect()
    };
    let r_segments: &[Segment] = &segments_vec;

    match encoder.construct_chunks(r_segments) {
        Ok(result) => {
            let total_chunks = result.len() * TOTAL_SHARDS;
            let mut chunk_ptrs: Vec<*mut [u8; 12]> = Vec::with_capacity(total_chunks);

            for boxed_array in result {
                for chunk in boxed_array.iter() {
                    chunk_ptrs.push(Box::into_raw(Box::new(*chunk)));
                }
            }

            unsafe {
                *out_chunks = chunk_ptrs.as_mut_ptr();
                *out_len = total_chunks;
            }

            std::mem::forget(chunk_ptrs);
            unsafe { *success = true };
        }
        Err(_) => {
            unsafe { *success = false };
        }
    }
}

/// Initializes a new SubShardDecoder.
#[no_mangle]
pub extern "C" fn subshard_decoder_new() -> *mut SubShardDecoder {
    Box::into_raw(Box::new(SubShardDecoder::new().unwrap()))
}

/// Frees the SubShardDecoder.
#[no_mangle]
pub extern "C" fn subshard_decoder_free(decoder: *mut SubShardDecoder) {
    if !decoder.is_null() {
        unsafe {
            drop(Box::from_raw(decoder));
        };
    }
}

#[repr(C)]
pub struct SegmentTuple {
    pub index: u8,
    pub segment: CSegment,
}

/// Result of the reconstruct.
#[repr(C)]
pub struct ReconstructResult {
    pub segments: *mut SegmentTuple,
    pub num_segments: usize,
    pub num_decodes: usize,
}

// #[no_mangle]
// pub extern "C" fn reconstruct_result_get_segments(
//     result: *const ReconstructResult,
// ) -> *const SegmentTuple {
//     if result.is_null() {
//         return std::ptr::null();
//     }
//     unsafe { (*result).segments }
// }

// #[no_mangle]
// pub extern "C" fn reconstruct_result_get_num_segments(result: *const ReconstructResult) -> usize {
//     if result.is_null() {
//         return 0;
//     }
//     unsafe { (*result).num_segments }
// }

// #[no_mangle]
// pub extern "C" fn reconstruct_result_get_num_decodes(result: *const ReconstructResult) -> usize {
//     if result.is_null() {
//         return 0;
//     }
//     unsafe { (*result).num_decodes }
// }

// #[no_mangle]
// pub extern "C" fn reconstruct_result_free(result: *mut ReconstructResult) {
//     if !result.is_null() {
//         unsafe {
//             let boxed_result = Box::from_raw(result);
//             drop(Box::from_raw(boxed_result.segments));
//             drop(boxed_result);
//         }
//     }
// }

#[repr(C)]
pub struct SubShardTuple {
    pub seg_index: u8,
    pub chunk_index: ChunkIndex,
    pub shard: [u8; 12],
}

/// Reconstructs data from a list of subshards.
#[no_mangle]
pub extern "C" fn subshard_decoder_reconstruct(
    decoder: *mut SubShardDecoder,
    subshards: *const SubShardTuple,
    num_subshards: usize,
    success: *mut bool,
) -> *mut ReconstructResult {
    if decoder.is_null() || subshards.is_null() {
        unsafe { *success = false };
        return std::ptr::null_mut();
    }

    let decoder = unsafe { &mut *decoder };
    let subshards_slice = unsafe { slice::from_raw_parts(subshards, num_subshards) };

    let cloned_subshards: Vec<(u8, ChunkIndex, &[u8; 12])> = subshards_slice
        .iter()
        .map(|t| (t.seg_index, t.chunk_index, &t.shard))
        .collect();

    match decoder.reconstruct(&mut cloned_subshards.iter().cloned()) {
        Ok((segments, num_decodes)) => {
            let mut segments_vec: Vec<SegmentTuple> = segments
                .into_iter()
                .map(|(index, segment)| SegmentTuple {
                    index,
                    segment: segment.into(),
                })
                .collect();
            let segments_len = segments_vec.len();
            let segments_ptr = segments_vec.as_mut_ptr();

            std::mem::forget(segments_vec); // prevent the Vec from being deallocated

            let result = ReconstructResult {
                segments: segments_ptr,
                num_segments: segments_len,
                num_decodes,
            };
            unsafe { *success = true };
            Box::into_raw(Box::new(result))
        }
        Err(_) => {
            unsafe { *success = false };
            std::ptr::null_mut()
        }
    }
}
