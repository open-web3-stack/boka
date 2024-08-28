// The Swift Programming Language
// https://docs.swift.org/swift-book
import msquic

func msquicInit() -> Int32 {
    let rawPointerPointer = UnsafeMutablePointer<
        UnsafeRawPointer?
    >.allocate(capacity: 1)
    //    rawPointerPointer.pointee = apiTablePointer
    // let status = MsQuicOpenVersion(2, rawPointerPointer)
    let status = MsQuicOpenVersion(2, rawPointerPointer)

    if status != 0 {
        print("MsQuicOpenVersion failed with status \(status)")
        return 0
    }
    print("MsQuicOpenVersion suceess with status \(status)")

    return 1
}
