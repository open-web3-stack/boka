use erasure_coding::{
    ChunkIndex, Segment, SubShardDecoder, SubShardEncoder, SEGMENT_SIZE, TOTAL_SHARDS,
};
use std::{ptr, slice};

/// Fixed size segment of a larger data.
/// Data is padded when unaligned with
/// the segment size.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct CSegment {
    /// Fix size chunk of data. Length is `SEGMENT_SIZE``
    data: *mut u8,
    /// The index of this segment against its full data.
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
/// A chunk is a group of subshards `[[u8; 12]; TOTAL_SHARDS]`.
///
/// out_chunks is N chunks `[[u8; 12]; TOTAL_SHARDS]` flattened to 1 dimensional u8 array.
/// out_len is N * TOTAL_SHARDS
#[no_mangle]
pub extern "C" fn subshard_encoder_construct(
    encoder: *mut SubShardEncoder,
    segments: *const CSegment,
    num_segments: usize,
    success: *mut bool,
    out_chunks: *mut u8,
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
            let mut data: Vec<u8> = Vec::with_capacity(total_chunks);

            for boxed_array in result {
                for chunk in boxed_array.iter() {
                    data.extend_from_slice(chunk);
                }
            }

            unsafe {
                ptr::copy_nonoverlapping(data.as_ptr(), out_chunks, data.len());
                *out_len = total_chunks;
            }

            std::mem::forget(data);
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
#[derive(Debug)]
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

#[no_mangle]
pub extern "C" fn reconstruct_result_free(result: *mut ReconstructResult) {
    if !result.is_null() {
        unsafe {
            let boxed_result = Box::from_raw(result);

            // free each CSegment's data pointer
            for i in 0..boxed_result.num_segments {
                let segment = &*boxed_result.segments.add(i);
                if !segment.segment.data.is_null() {
                    drop(Box::from_raw(segment.segment.data));
                }
            }

            drop(Box::from_raw(boxed_result.segments));
            drop(boxed_result);
        }
    }
}

#[repr(C)]
#[derive(Debug)]
pub struct SubShardTuple {
    pub seg_index: u8,
    pub chunk_index: ChunkIndex,
    pub subshard: [u8; 12],
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
        return ptr::null_mut();
    }

    let decoder = unsafe { &mut *decoder };
    let subshards_slice = unsafe { slice::from_raw_parts(subshards, num_subshards) };

    let subshards_vec: Vec<(u8, ChunkIndex, &[u8; 12])> = subshards_slice
        .iter()
        .map(|t| (t.seg_index, t.chunk_index, &t.subshard))
        .collect();

    match decoder.reconstruct(&mut subshards_vec.iter().cloned()) {
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

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;
    use erasure_coding::{SubShard, SUBSHARD_SIZE};
    use serde::{Deserialize, Serialize};
    use serde_json;

    #[derive(Serialize, Deserialize, Debug)]
    struct JsonData {
        data: String,
        segment: SegmentData,
    }

    #[derive(Serialize, Deserialize, Debug)]
    struct SegmentData {
        segments: Vec<Segment>,
    }

    #[derive(Serialize, Deserialize, Debug)]
    struct Segment {
        segment_ec: Vec<String>,
    }

    #[test]
    fn test_reconstruct_from_json() {
        let file =
            fs::File::open("../../Tests/UtilsTests/TestData/ec/erasure-coding-test-data.json")
                .expect("file should open read only");
        let json_data: JsonData =
            serde_json::from_reader(file).expect("file should be proper JSON");

        // Convert segment_ec data back to bytes and prepare subshards
        let mut subshards: Vec<(u8, ChunkIndex, SubShard)> = Vec::new();
        for (segment_idx, segment) in json_data.segment.segments.iter().enumerate() {
            for (chunk_idx, chunk) in segment.segment_ec.iter().enumerate() {
                let chunk_bytes: Vec<u8> = hex::decode(chunk).expect("Failed to decode hex string");
                if chunk_idx >= 684 {
                    let mut subshard = [0u8; SUBSHARD_SIZE];
                    subshard[..chunk_bytes.len()].copy_from_slice(&chunk_bytes);
                    subshards.push((segment_idx as u8, ChunkIndex(chunk_idx as u16), subshard));
                }
            }
        }

        // Initialize decoder, call reconstruct!
        let mut decoder = SubShardDecoder::new().unwrap();

        let cloned_subshards: Vec<(u8, ChunkIndex, &[u8; 12])> =
            subshards.iter().map(|t| (t.0, t.1, &t.2)).collect();

        let (reconstructed_segments, _nb_decode) = decoder
            .reconstruct(&mut cloned_subshards.iter().cloned())
            .unwrap();

        // Check the result
        // println!("Reconstructed Segments: {:x?}", reconstructed_segments);
        // println!("Number of Decodes: {}", nb_decode);

        assert_eq!(reconstructed_segments.len(), 1);
        let original_data_bytes =
            hex::decode(&json_data.data).expect("Failed to decode hex string");
        // Verify that the data attribute matches the first 342 bytes of the reconstructed data in the first segment
        if let Some((_, first_segment)) = reconstructed_segments.get(0) {
            assert_eq!(
                &first_segment.data[..342],
                &original_data_bytes[..342],
                "The first 342 bytes of the reconstructed data do not match the original data."
            );
            println!("Reconstructed successfully! YAY");
        } else {
            panic!("No reconstructed segments found.");
        }
    }
}
