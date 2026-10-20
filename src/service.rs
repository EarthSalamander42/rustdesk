use librustdesk::*;

#[cfg(not(target_os = "macos"))]
fn main() {}

#[cfg(target_os = "macos")]
fn main() {
    let args: Vec<String> = std::env::args().collect();
    // FS Support (20/10/2026) : sans cela le service gardait le nom « RustDesk » (plists, IPC
    // /tmp/RustDesk-service, configuration) alors que l'interface s'appelle « FS Support ».
    crate::common::load_custom_client();
    librustdesk::fs_support_apply_defaults();
    if args.len() > 1 && args[1] == "--write-plists" {
        if let Err(e) = librustdesk::platform::write_plists() {
            eprintln!("Failed to write plists: {}", e);
            std::process::exit(1);
        }
        std::process::exit(0);
    }
    hbb_common::init_log(false, "service");
    crate::start_os_service();
}
