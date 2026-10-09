// Pas de sous-système « windows » pour les tests : le harnais de test écrit sur la console.
#![cfg_attr(not(test), windows_subsystem = "windows")]

use std::{
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use bin_reader::{normalize_path, BinaryReader};

pub mod bin_reader;
mod cleanup;
#[cfg(windows)]
mod ui;

#[cfg(windows)]
const APP_METADATA: &[u8] = include_bytes!("../app_metadata.toml");
#[cfg(not(windows))]
const APP_METADATA: &[u8] = &[];
const APP_METADATA_CONFIG: &str = "meta.toml";
const META_LINE_PREFIX_TIMESTAMP: &str = "timestamp = ";
const META_LINE_PREFIX_FILE: &str = "file = ";
// Nom de l'exécutable de la charge générique, et ancien dossier d'extraction commun.
#[cfg_attr(not(windows), allow(dead_code))]
const APP_PREFIX: &str = "rustdesk";
const APPNAME_RUNTIME_ENV_KEY: &str = "RUSTDESK_APPNAME";
#[cfg(windows)]
const SET_FOREGROUND_WINDOW_ENV_KEY: &str = "SET_FOREGROUND_WINDOW";

// ---------------------------------------------------------------------------
// FS Support : un dossier d'extraction par version (09/10/2026).
//
// Le paquet téléchargé (`fs-support-<version>-windows-x86_64.exe`) se décompressait toujours dans
// `%LOCALAPPDATA%\rustdesk`. Quand une copie lancée de là tournait encore, `rustdesk.exe` et
// `librustdesk.dll` étaient verrouillés : la nouvelle version n'écrasait que les fichiers libres,
// réécrivait `meta.toml`, puis relançait l'ANCIEN binaire, y compris pour `--update`. La mise à
// jour de l'installation échouait donc toujours avec l'ancien code.
//
// Désormais : `%LOCALAPPDATA%\<application>\app-<version>-<build>\<application>.exe`, un dossier
// neuf pour chaque build, jamais partagé avec une autre version. Les anciens dossiers sont
// supprimés après le lancement s'ils ne servent plus (module `cleanup`).
// Nom et version viennent du workflow, comme pour `src/fs_support.rs` et `build.rs`.
// ---------------------------------------------------------------------------

/// Nom de l'application quand le workflow n'en fournit pas (même repli que `src/fs_support.rs`).
const DEFAULT_APP_NAME: &str = "FS Support";
/// Préfixe des dossiers d'extraction, un par build.
const EXTRACTION_PREFIX: &str = "app-";
/// Marqueur d'une extraction FS Support dans l'ancien dossier commun (ressources du paquet
/// `fs_ui`) : un `rustdesk` sans ce marqueur peut appartenir à un RustDesk portable, jamais touché.
#[cfg_attr(not(windows), allow(dead_code))]
const FS_LEGACY_MARKER: &str = "data/flutter_assets/packages/fs_ui";

/// Composant de chemin sûr sous Windows : ni vide, ni « . » ou « .. », ni séparateur, caractère
/// interdit, caractère de contrôle, point ou espace final.
fn is_safe_dir_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 64
        && name != "."
        && name != ".."
        && !name.ends_with('.')
        && !name.ends_with(' ')
        && !name
            .chars()
            .any(|c| c.is_control() || "\\/:*?\"<>|".contains(c))
}

/// Nom de l'application : dossier `%LOCALAPPDATA%\<nom>` et exécutable `<nom>.exe`.
fn app_name() -> String {
    let name = option_env!("FS_SUPPORT_APP_NAME").unwrap_or("").trim();
    if is_safe_dir_name(name) {
        name.to_owned()
    } else {
        DEFAULT_APP_NAME.to_owned()
    }
}

/// Version réduite aux caractères sûrs dans un nom de dossier (« 1.0.109 »).
fn sanitize_version(version: &str) -> String {
    let version: String = version
        .trim()
        .chars()
        .take(32)
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let version = version.trim_matches('.');
    if version.is_empty() {
        "0".to_owned()
    } else {
        version.to_owned()
    }
}

fn app_version() -> String {
    let version = option_env!("FS_SUPPORT_BASE_VERSION").unwrap_or("").trim();
    sanitize_version(if version.is_empty() {
        env!("CARGO_PKG_VERSION")
    } else {
        version
    })
}

/// `app-<version>-<horodatage du build, en secondes, hexadécimal>` : deux builds d'une même
/// version ne partagent pas non plus leur dossier.
fn extraction_dir_name(version: &str, build_timestamp: u64) -> String {
    if build_timestamp == 0 {
        format!("{}{}", EXTRACTION_PREFIX, version)
    } else {
        format!(
            "{}{}-{:08x}",
            EXTRACTION_PREFIX,
            version,
            build_timestamp / 1000
        )
    }
}

/// Horodatage du build (millisecondes) écrit par `generate.py` ; 0 s'il manque.
fn build_timestamp() -> u64 {
    let Ok(app_metadata) = std::str::from_utf8(APP_METADATA) else {
        return 0;
    };
    for line in app_metadata.lines() {
        if let Some(value) = line.strip_prefix(META_LINE_PREFIX_TIMESTAMP) {
            if let Ok(ts) = value.trim().parse::<u64>() {
                return ts;
            }
        }
    }
    0
}

fn is_timestamp_matches(dir: &Path, ts: &mut u64) -> bool {
    *ts = build_timestamp();
    if *ts == 0 {
        return true;
    }

    if let Ok(content) = std::fs::read_to_string(dir.join(APP_METADATA_CONFIG)) {
        for line in content.lines() {
            if line.starts_with(META_LINE_PREFIX_TIMESTAMP) {
                if let Ok(stored_ts) = line.replace(META_LINE_PREFIX_TIMESTAMP, "").parse::<u64>() {
                    return *ts == stored_ts;
                }
            }
        }
    }
    false
}

fn write_meta(dir: &Path, ts: u64, package_paths: &[String]) {
    let meta_file = dir.join(APP_METADATA_CONFIG);
    let mut content = format!("{}{}\n", META_LINE_PREFIX_TIMESTAMP, ts);
    for path in package_paths {
        content.push_str(&format!("{}{}\n", META_LINE_PREFIX_FILE, path));
    }
    // Ignore is ok here
    let _ = std::fs::write(meta_file, content);
}

fn previous_package_files(dir: &Path) -> Vec<String> {
    let Ok(content) = std::fs::read_to_string(dir.join(APP_METADATA_CONFIG)) else {
        return Vec::new();
    };
    content
        .lines()
        .filter_map(|line| line.strip_prefix(META_LINE_PREFIX_FILE))
        .map(|path| path.trim().to_owned())
        .collect()
}

// meta.toml is plain text in a user-writable directory, and it now drives deletion,
// so the path is rebuilt from plain components rather than joined as written. A
// prefix, root or parent component would otherwise escape the extraction directory:
// Path::join replaces the base entirely when given an absolute path.
fn resolve_within(dir: &Path, relative: &str) -> Option<PathBuf> {
    use std::path::Component;
    let mut path = dir.to_path_buf();
    let mut any = false;
    for component in Path::new(&relative.replace('\\', "/")).components() {
        match component {
            Component::Normal(part) => {
                // A drive-relative name like "C:x" parses as Normal, and only a
                // Windows host would classify "C:/..." as a Prefix, so the colon is
                // rejected outright rather than relying on the host's parser.
                if part.to_string_lossy().contains(':') {
                    return None;
                }
                path.push(part);
                any = true;
            }
            Component::CurDir => {}
            _ => return None,
        }
    }
    if any {
        Some(path)
    } else {
        None
    }
}

// A customer who drops a branding asset gets a package without it, and the file
// would otherwise linger in an existing extraction and keep being used. The wipe
// cannot cover this: it is keyed on the packer's build timestamp, which is now the
// same for every customer of a release.
fn remove_dropped_package_files_with<F>(
    dir: &Path,
    current: &[String],
    mut remove_file: F,
) -> Vec<String>
where
    F: FnMut(&Path) -> std::io::Result<()>,
{
    let keep: std::collections::HashSet<String> =
        current.iter().map(|p| normalize_path(p)).collect();
    let mut failed = Vec::new();
    for previous in previous_package_files(dir) {
        if keep.contains(&normalize_path(&previous)) {
            continue;
        }
        let Some(path) = resolve_within(dir, &previous) else {
            continue;
        };
        if path.is_file() {
            println!("removing dropped {}", previous);
            if let Err(error) = remove_file(&path) {
                eprintln!("failed to remove dropped {}: {}", previous, error);
                failed.push(previous);
            }
        }
    }
    failed
}

fn remove_dropped_package_files(dir: &Path, current: &[String]) -> Vec<String> {
    remove_dropped_package_files_with(dir, current, |path| std::fs::remove_file(path))
}

/// Dossier d'extraction et exécutable à lancer.
fn setup(
    reader: BinaryReader,
    dir: Option<PathBuf>,
    clear: bool,
    _args: &Vec<String>,
    _ui: &mut bool,
) -> Option<(PathBuf, PathBuf)> {
    let dir = if let Some(dir) = dir {
        dir
    } else {
        // FS Support : `%LOCALAPPDATA%\<application>\app-<version>-<build>` (voir plus haut).
        if let Some(dir) = dirs::data_local_dir() {
            dir.join(app_name())
                .join(extraction_dir_name(&app_version(), build_timestamp()))
        } else {
            eprintln!("not found data local dir");
            return None;
        }
    };

    let mut ts = build_timestamp();
    if clear || !is_timestamp_matches(&dir, &mut ts) {
        #[cfg(windows)]
        if _args.is_empty() {
            *_ui = true;
            ui::setup();
        }
        std::fs::remove_dir_all(&dir).ok();
    }
    let mut metadata_paths = reader.package_paths.clone();
    metadata_paths.extend(remove_dropped_package_files(&dir, &reader.package_paths));
    for file in reader.files.iter() {
        file.write_to_file(&dir);
    }
    write_meta(&dir, ts, &metadata_paths);
    #[cfg(windows)]
    win::copy_runtime_broker(&dir);
    #[cfg(linux)]
    reader.configure_permission(&dir);
    let exe = dir.join(&reader.exe);
    Some((dir, exe))
}

fn use_null_stdio() -> bool {
    #[cfg(windows)]
    {
        // When running in CMD on Windows 7, using Stdio::inherit() with spawn returns an "invalid handle" error.
        // Since using Stdio::null() didn’t cause any issues, and determining whether the program is launched from CMD or by double-clicking would require calling more APIs during startup, we also use Stdio::null() when launched by double-clicking on Windows 7.
        let is_windows_7 = is_windows_7();
        println!("is windows7: {}", is_windows_7);
        return is_windows_7;
    }
    #[cfg(not(windows))]
    false
}

#[cfg(windows)]
fn is_windows_7() -> bool {
    use windows::Wdk::System::SystemServices::RtlGetVersion;
    use windows::Win32::System::SystemInformation::OSVERSIONINFOW;

    unsafe {
        let mut version_info = OSVERSIONINFOW::default();
        version_info.dwOSVersionInfoSize = std::mem::size_of::<OSVERSIONINFOW>() as u32;

        if RtlGetVersion(&mut version_info).is_ok() {
            // Windows 7 is version 6.1
            println!(
                "Windows version: {}.{}",
                version_info.dwMajorVersion, version_info.dwMinorVersion
            );
            return version_info.dwMajorVersion == 6 && version_info.dwMinorVersion == 1;
        }
    }
    false
}

fn execute(path: PathBuf, args: Vec<String>, _ui: bool) {
    println!("executing {}", path.display());
    // setup env
    let exe = std::env::current_exe().unwrap_or_default();
    let exe_name = exe.file_name().unwrap_or_default();
    // run executable
    let mut cmd = Command::new(path);
    cmd.args(args);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(winapi::um::winbase::CREATE_NO_WINDOW);
        if _ui {
            cmd.env(SET_FOREGROUND_WINDOW_ENV_KEY, "1");
        }
    }

    cmd.env(APPNAME_RUNTIME_ENV_KEY, exe_name);
    if use_null_stdio() {
        cmd.stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
    } else {
        cmd.stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit());
    }
    let _child = cmd.spawn();

    #[cfg(windows)]
    if _ui {
        match _child {
            Ok(child) => unsafe {
                winapi::um::winuser::AllowSetForegroundWindow(child.id() as u32);
            },
            Err(e) => {
                eprintln!("{:?}", e);
            }
        }
    }
}

fn main() -> Result<(), String> {
    let mut args = Vec::new();
    let mut arg_exe = Default::default();
    let mut i = 0;
    for arg in std::env::args() {
        if i == 0 {
            arg_exe = arg.clone();
        } else {
            args.push(arg);
        }
        i += 1;
    }
    let click_setup = args.is_empty() && arg_exe.to_lowercase().ends_with("install.exe");
    #[cfg(windows)]
    let quick_support = args.is_empty() && win::is_quick_support_exe(&arg_exe);
    #[cfg(not(windows))]
    let quick_support = false;

    let mut ui = false;
    #[allow(unused_mut)]
    let mut reader = BinaryReader::new()?;
    // FS Support : l'exécutable décompressé porte le nom de l'application (« FS Support.exe »),
    // comme l'exécutable installé. `update_me` / `install_me` n'ont alors plus rien à renommer.
    #[cfg(windows)]
    reader.rename_stock_executable(APP_PREFIX, &format!("./{}.exe", app_name()));
    if let Some((_dir, exe)) = setup(
        reader,
        None,
        click_setup || args.contains(&"--silent-install".to_owned()),
        &args,
        &mut ui,
    ) {
        if click_setup {
            args = vec!["--install".to_owned()];
        } else if quick_support {
            args = vec!["--quick_support".to_owned()];
        }
        execute(exe, args, ui);
        // Après le lancement, pour ne pas le retarder : anciens dossiers d'extraction qui ne
        // servent plus. Windows seulement : le test « en cours d'utilisation » repose sur le
        // verrouillage des fichiers par Windows.
        #[cfg(windows)]
        if let Some(local) = dirs::data_local_dir() {
            cleanup::remove_old_extractions(&_dir, &local.join(APP_PREFIX));
        }
    }
    Ok(())
}

#[cfg(windows)]
mod win {
    use std::{fs, os::windows::process::CommandExt, path::Path, process::Command};

    // Used for privacy mode(magnifier impl).
    pub const RUNTIME_BROKER_EXE: &'static str = "C:\\Windows\\System32\\RuntimeBroker.exe";
    pub const WIN_TOPMOST_INJECTED_PROCESS_EXE: &'static str = "RuntimeBroker_rustdesk.exe";

    pub(super) fn copy_runtime_broker(dir: &Path) {
        let src = RUNTIME_BROKER_EXE;
        let tgt = WIN_TOPMOST_INJECTED_PROCESS_EXE;
        let target_file = dir.join(tgt);
        if target_file.exists() {
            if let (Ok(src_file), Ok(tgt_file)) = (fs::read(src), fs::read(&target_file)) {
                let src_md5 = format!("{:x}", md5::compute(&src_file));
                let tgt_md5 = format!("{:x}", md5::compute(&tgt_file));
                if src_md5 == tgt_md5 {
                    return;
                }
            }
        }
        let _allow_err = Command::new("taskkill")
            .args(&["/F", "/IM", "RuntimeBroker_rustdesk.exe"])
            .creation_flags(winapi::um::winbase::CREATE_NO_WINDOW)
            .output();
        let _allow_err = std::fs::copy(src, &format!("{}\\{}", dir.to_string_lossy(), tgt));
    }

    /// Check if the executable is a Quick Support version.
    /// Note: This function must be kept in sync with `src/core_main.rs`.
    #[inline]
    pub(super) fn is_quick_support_exe(exe: &str) -> bool {
        let exe = exe.to_lowercase();
        exe.contains("-qs-") || exe.contains("-qs.exe") || exe.contains("_qs.exe")
    }
}

#[cfg(test)]
mod meta_tests {
    use super::*;

    #[test]
    fn resolve_within_rejects_paths_that_escape() {
        let base = Path::new("/base");
        assert_eq!(
            resolve_within(base, "./data/logo.png"),
            Some(base.join("data").join("logo.png"))
        );
        assert_eq!(
            resolve_within(base, ".\\data\\logo.png"),
            Some(base.join("data").join("logo.png"))
        );
        // meta.toml is user-writable, so these must not reach remove_file.
        assert_eq!(resolve_within(base, "../../etc/passwd"), None);
        assert_eq!(resolve_within(base, "/etc/passwd"), None);
        assert_eq!(resolve_within(base, "C:\\Windows\\System32\\x.dll"), None);
        assert_eq!(resolve_within(base, "."), None);
        assert_eq!(resolve_within(base, ""), None);
    }

    #[test]
    fn fs_extraction_un_dossier_par_build() {
        assert_eq!(
            extraction_dir_name("1.0.109", 1_760_000_000_123),
            "app-1.0.109-68e77800"
        );
        assert_eq!(extraction_dir_name("1.0.109", 0), "app-1.0.109");
        // Deux builds de la même version ne partagent pas leur dossier.
        assert_ne!(
            extraction_dir_name("1.0.109", 1_760_000_000_000),
            extraction_dir_name("1.0.109", 1_760_000_100_000)
        );
        let name = extraction_dir_name(&app_version(), build_timestamp());
        assert!(name.starts_with(EXTRACTION_PREFIX) && is_safe_dir_name(&name));
    }

    #[test]
    fn fs_extraction_noms_de_dossier_surs() {
        assert_eq!(sanitize_version("1.0.109"), "1.0.109");
        assert_eq!(sanitize_version(" 1.0.109-beta_2 "), "1.0.109-beta_2");
        assert_eq!(sanitize_version("1.0/../x"), "1.0_.._x");
        assert_eq!(sanitize_version("C:\\x"), "C__x");
        assert_eq!(sanitize_version(""), "0");
        assert_eq!(sanitize_version(".."), "0");
        assert!(is_safe_dir_name("FS Support"));
        for bad in ["", ".", "..", "a/b", "a\\b", "a:b", "x.", "x ", "a*b", "a\u{1}b"] {
            assert!(!is_safe_dir_name(bad), "{:?}", bad);
        }
        let name = app_name();
        assert!(is_safe_dir_name(&name), "{:?}", name);
    }
}
