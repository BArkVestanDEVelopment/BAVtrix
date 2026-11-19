fn main() {
    let _ = embed_resource::compile("setup.rc", embed_resource::NONE);
    println!("cargo:rerun-if-changed=setup.rc");
    println!("cargo:rerun-if-changed=setup.manifest");
    println!("cargo:rerun-if-changed=../release/1.0/bavtrix.exe");
}
