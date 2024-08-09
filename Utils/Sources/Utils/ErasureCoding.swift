import erasure_coding
import Foundation

public enum ErasureCodeError: Error {
    case constructFailed
    case reconstructFailed
}

/// Split original data into segments
public func split(data: Data) -> [CSegment] {
    var segments: [CSegment] = []
    let segmentSize = Int(SEGMENT_SIZE)

    for i in stride(from: 0, to: data.count, by: segmentSize) {
        let end = min(i + segmentSize, data.count)
        let segmentData = data[i ..< end]
        let index = UInt32(i / segmentSize)

        let segment = CSegment(
            data: UnsafeMutablePointer(mutating: segmentData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }),
            index: index
        )
        segments.append(segment)
    }

    // Check and pad the last segment if needed
    let remainder = data.count % segmentSize
    if remainder > 0 {
        // Create a padded segment
        var paddedData = Data(count: segmentSize)
        let start = data.count - remainder
        let segmentData = data[start ..< data.count]

        // Copy data and pad
        paddedData.replaceSubrange(0 ..< remainder, with: segmentData)

        let index = UInt32(segments.count)

        let segment = CSegment(
            data: UnsafeMutablePointer(mutating: paddedData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }),
            index: index
        )
        segments[segments.count - 1] = segment
    }

    return segments
}

/// Join segments into original data (with padding)
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
    ///
    /// TODO: note the underlying rust lib is not compatible to GP yet, so this will be changed
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

    /// Reconstruct erasure-coded chunks to segments
    public func reconstruct(subshards: [SubShardTuple]) -> Result<ReconstructResult, ErasureCodeError> {
        var success = false

        let reconstructResult = subshards.withUnsafeBufferPointer { subshardsPtr in
            subshard_decoder_reconstruct(decoder, subshardsPtr.baseAddress, UInt(subshards.count), &success)
        }

        guard success, let result = reconstructResult
        else {
            return .failure(.reconstructFailed)
        }

        return .success(result.pointee)
    }
}
