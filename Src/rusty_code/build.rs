// Build-scripts also need to be linked. Emit a small amount of diagnostic
// information (as cargo warnings) so CI logs capture the environment used to
// build the crate. This helps debugging cross-toolchain/CI issues.
use std::env;
use std::process::Command;


fn main() {
    // Print a selected set of environment variables so the build log records
    // the values Corrosion/CMake may have set for the crate build.
    let keys = [
        "CC",
        "CXX",
        "CXXFLAGS",
        "SCCACHE_DISABLE",
        "CARGO_BUILD_RUSTC",
        "CORROSION_BUILD_DIR",
        "TARGET",
        "PROFILE",
        "OUT_DIR",
        "CARGO_MANIFEST_DIR",
    ];

    for k in &keys {
        let v = env::var(k).unwrap_or_else(|_| "<unset>".to_string());
        println!("cargo:warning=build.rs: {}={}", k, v);
    }

    // Capture rustc/cargo versions when available; these are useful in CI
    // diagnostics. We only query --version to avoid invoking nested builds.
    if let Ok(out) = Command::new("rustc").arg("--version").output() {
        if let Ok(s) = String::from_utf8(out.stdout) {
            println!("cargo:warning=build.rs: rustc version: {}", s.trim());
        }
    }
    if let Ok(out) = Command::new("cargo").arg("--version").output() {
        if let Ok(s) = String::from_utf8(out.stdout) {
            println!("cargo:warning=build.rs: cargo version: {}", s.trim());
        }
    }

    // (No cfg aliases emitted by default.)

    // ── CXX bridge ─────────────────────────────────────────────────
    // NOTE: `#[cfg(not(target_arch = "wasm32"))]` checks the *host* triple
    // inside a build script, NOT the crate's target.  Use the `CARGO_CFG_*`
    // environment variable so that cross-compiling to wasm32 correctly skips
    // the CXX bridge build.
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
    // Build the CXX bridge for native (non-wasm) targets. The bridge
    // implementation lives in `src/lib.rs`, so scan that file.
    if target_arch != "wasm32" {
        cxx_build::bridge("src/lib.rs")
            .std("c++17")
            .compile("rusty_code");
    } else {
        println!("cargo:warning=build.rs: skipping cxx bridge for wasm32 target");
    }

    println!("cargo:warning=build.rs: Build-script completed.");
}
