fn main() {
    #[cfg(windows)]
    {
        use std::io::Write;
        use winres::VersionInfo;
        let mut res = winres::WindowsResource::new();
        let version = std::env::var("FS_SUPPORT_BASE_VERSION")
            .unwrap_or_else(|_| env!("CARGO_PKG_VERSION").to_owned());
        let numeric_version = windows_numeric_version(&version);
        res.set_icon("../../res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("../../res/manifest.xml")
            .set("FileVersion", &version)
            .set("ProductVersion", &version)
            .set_version_info(VersionInfo::FILEVERSION, numeric_version)
            .set_version_info(VersionInfo::PRODUCTVERSION, numeric_version);
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}

#[cfg(windows)]
fn windows_numeric_version(version: &str) -> u64 {
    let mut parts = [0_u64; 4];
    for (index, part) in version
        .split(|c| c == '.' || c == '-')
        .take(4)
        .enumerate()
    {
        parts[index] = part.parse::<u64>().unwrap_or(0).min(u16::MAX as u64);
    }
    (parts[0] << 48) | (parts[1] << 32) | (parts[2] << 16) | parts[3]
}
