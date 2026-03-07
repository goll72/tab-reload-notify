use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS")?;

    if target_os == "windows" {
        embed_resource::compile("resources.rc", embed_resource::NONE).manifest_optional()?;

        println!("cargo:rerun-if-changed=resources.rc");
        println!("cargo:rerun-if-changed=icon.ico");
    }

    Ok(())
}
