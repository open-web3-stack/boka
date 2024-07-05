use ark_ec_vrfs::suites::bandersnatch::edwards::RingContext;
use bandersnatch::*;

mod bandersnatch;

#[swift_bridge::bridge]
mod ffi {
    // Export opaque Rust types, functions and methods for Swift to use.
    extern "Rust" {
        type IetfVrfSignature;
        type RingVrfSignature;
        type RingContext;

        #[swift_bridge(swift_name = "ringContext")]
        fn ring_context() -> &'static RingContext;
    }
}
