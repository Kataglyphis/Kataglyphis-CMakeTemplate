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

    // Proceed with the existing cxx build step.
    cxx_build::bridge("src/lib.rs")
        .std("c++17")
        .compile("rusty_code");

    println!("cargo:warning=build.rs: Build-script completed.");
}
