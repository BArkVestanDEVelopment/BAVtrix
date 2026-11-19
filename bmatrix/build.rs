fn main() {
    // Application manifest: Win8+ compatibility (layered child windows) and per-monitor DPI.
    let _ = embed_resource::compile("bmatrix.rc", embed_resource::NONE);
    println!("cargo:rerun-if-changed=bmatrix.manifest");
    println!("cargo:rerun-if-changed=bmatrix.ico");
    println!("cargo:rerun-if-changed=bmatrix.rc");
}
