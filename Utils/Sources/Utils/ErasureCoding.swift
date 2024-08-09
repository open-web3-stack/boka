import erasure_coding
import Foundation

// TODO: note the underlying rust lib is not compatible with GP yet, so these will be changed

public enum ErasureCodeError: Error {
    case constructFailed
    case reconstructFailed
}

/// Split original data into segments
public func split(data: Data) -> [CSegment] {
    var segments: [CSegment] = []
    let segmentSize = Int(SEGMENT_SIZE)

    // Create a new data with padding
    var paddedData = data
    let remainder = data.count % segmentSize
    if remainder != 0 {
        paddedData.append(Data(repeating: 0, count: segmentSize - remainder))
    }

    for i in stride(from: 0, to: paddedData.count, by: segmentSize) {
        let end = min(i + segmentSize, data.count)
        let segmentData = paddedData[i ..< end]
        let index = UInt32(i / segmentSize)

        let segment = CSegment(
            data: UnsafeMutablePointer(mutating: segmentData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }),
            index: index
        )
        segments.append(segment)
    }

    return segments
}

/// Join segments into original data (padding not removed)
private func join(segments: [CSegment]) -> Data {
    var data = Data()
    let sortedSegments = segments.sorted { $0.index < $1.index }

    for segment in sortedSegments {
        let segmentData = UnsafeBufferPointer(start: segment.data, count: Int(SEGMENT_SIZE))
        data.append(segmentData)
    }

    return data
}

public class SubShardEncoder {
    private let encoder: OpaquePointer

    public init() {
        encoder = subshard_encoder_new()
    }

    deinit {
        subshard_encoder_free(encoder)
    }

    /// Construct erasure-coded chunks from segments
    public func construct(segments: [CSegment]) -> Result<[UInt8], ErasureCodeError> {
        var success = false
        var out_len: UInt = 0

        let expectedOutLen = Int(SUBSHARD_SIZE) * Int(TOTAL_SHARDS) * segments.count
        var out_chunks = [UInt8](repeating: 0, count: expectedOutLen)

        segments.withUnsafeBufferPointer { segmentsPtr in
            subshard_encoder_construct(encoder, segmentsPtr.baseAddress, UInt(segments.count), &success, &out_chunks, &out_len)
        }

        guard success, expectedOutLen == Int(out_len) else {
            return .failure(.constructFailed)
        }

        return .success(out_chunks)
    }
}

public class SubShardDecoder {
    private let decoder: OpaquePointer

    public init() {
        decoder = subshard_decoder_new()
    }

    deinit {
        subshard_decoder_free(decoder)
    }

    public class Decoded {
        private var result: UnsafeMutablePointer<ReconstructResult>

        public let segments: [SegmentTuple]
        public let numDecoded: UInt

        init(_ res: UnsafeMutablePointer<ReconstructResult>) {
            result = res
            let numSegments = Int(result.pointee.num_segments)
            let segmentTuplesPtr = result.pointee.segments

            // Safely access the segments array
            let bufferPtr = UnsafeMutableBufferPointer<SegmentTuple>(start: segmentTuplesPtr, count: numSegments)
            segments = Array(bufferPtr)

            numDecoded = result.pointee.num_decodes
        }

        deinit {
            reconstruct_result_free(result)
        }
    }

    /// Reconstruct erasure-coded chunks to segments
    public func reconstruct(subshards: [SubShardTuple]) -> Result<Decoded, ErasureCodeError> {
        var success = false

        let reconstructResult = subshards.withUnsafeBufferPointer { subshardsPtr in
            subshard_decoder_reconstruct(decoder, subshardsPtr.baseAddress, UInt(subshards.count), &success)
        }

        guard success, let result = reconstructResult
        else {
            return .failure(.reconstructFailed)
        }

        return .success(Decoded(result))
    }
}
