import Foundation

public enum FFIUtils {
    private static func _call<E: Error>(
        data: [Data],
        out: inout Data?,
        fn: ([(ptr: UnsafeRawPointer, count: UInt)], (ptr: UnsafeMutableRawPointer, count: UInt)?) -> Int,
        onErr: (Int) throws(E) -> Void
    ) throws(E) {
        func helper(data: ArraySlice<Data>, ptr: [(ptr: UnsafeRawPointer, count: UInt)]) -> Int {
            guard let first = data.first else {
                if var outData = out {
                    let res = outData.withUnsafeMutableBytes { (bufferPtr: UnsafeMutableRawBufferPointer) -> Int in
                        guard let bufferAddress = bufferPtr.baseAddress else {
                            fatalError("unreachable: bufferPtr.baseAddress is nil")
                        }
                        return fn(ptr, (ptr: bufferAddress, count: UInt(bufferPtr.count)))
                    }
                    out = outData
                    return res
                }
                return fn(ptr, nil)
            }
            let rest = data.dropFirst()
            return first.withUnsafeBytes { (bufferPtr: UnsafeRawBufferPointer) -> Int in
                guard let bufferAddress = bufferPtr.baseAddress else {
                    fatalError("unreachable: bufferPtr.baseAddress is nil")
                }
                return helper(data: rest, ptr: ptr + [(bufferAddress, UInt(bufferPtr.count))])
            }
        }

        let ret = helper(data: data[...], ptr: [])

        if ret != 0 {
            try onErr(ret)
        }
    }

    static func call<E: Error>(
        _ data: Data...,
        fn: ([(ptr: UnsafeRawPointer, count: UInt)]) -> Int,
        onErr: (Int) throws(E) -> Void
    ) throws(E) {
        var out: Data?
        try _call(data: data, out: &out, fn: { ptrs, _ in fn(ptrs) }, onErr: onErr)
    }

    static func call(
        _ data: Data...,
        fn: ([(ptr: UnsafeRawPointer, count: UInt)]) -> Int
    ) {
        var out: Data?
        _call(data: data, out: &out, fn: { ptrs, _ in fn(ptrs) }, onErr: { err in fatalError("unreachable: \(err)") })
    }

    static func call<E: Error>(
        _ data: Data...,
        out: inout Data,
        fn: ([(ptr: UnsafeRawPointer, count: UInt)], (ptr: UnsafeMutableRawPointer, count: UInt)) -> Int,
        onErr: (Int) throws(E) -> Void
    ) throws(E) {
        var out2: Data? = out
        try _call(data: data, out: &out2, fn: { ptrs, out_buf in fn(ptrs, out_buf!) }, onErr: onErr)
        out = out2!
    }

    static func call(
        _ data: Data...,
        out: inout Data,
        fn: ([(ptr: UnsafeRawPointer, count: UInt)], (ptr: UnsafeMutableRawPointer, count: UInt)) -> Int
    ) {
        var out2: Data? = out
        _call(data: data, out: &out2, fn: { ptrs, out_buf in fn(ptrs, out_buf!) }, onErr: { err in fatalError("unreachable: \(err)") })
        out = out2!
    }

    private static func _withCString<R>(
        fn: ([UnsafePointer<CChar>?]) throws -> R,
        str: ArraySlice<String>,
        ptrs: [UnsafePointer<CChar>?]
    ) rethrows -> R {
        guard let first = str.first else {
            return try fn(ptrs)
        }
        let rest = str.dropFirst()
        return try first.withCString { ptr in
            try _withCString(fn: fn, str: rest, ptrs: ptrs + [ptr])
        }
    }

    public static func withCString<R>(_ str: [String], fn: ([UnsafePointer<CChar>?]) throws -> R) rethrows -> R {
        try _withCString(fn: fn, str: str[...], ptrs: [])
    }
}
