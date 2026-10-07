use hbb_common::{config::Config, log};

const FS_SUPPORT_PREFILL_VERSION: &str = "1";
const DEFAULT_FS_SUPPORT_VERSION: &str = "1.0.0";

fn build_value(value: Option<&'static str>) -> String {
    value.unwrap_or("").trim().to_owned()
}

fn has_existing_server_config() -> bool {
    !Config::get_option("custom-rendezvous-server").trim().is_empty()
        || !Config::get_option("rendezvous-servers").trim().is_empty()
        || !Config::get_option("key").trim().is_empty()
}

fn set_option_if_present(key: &str, value: &str) {
    let value = value.trim();
    if !value.is_empty() {
        Config::set_option(key.to_owned(), value.to_owned());
    }
}

pub fn apply_defaults() {
    let app_name = build_value(option_env!("FS_SUPPORT_APP_NAME"));
    let app_name = if app_name.is_empty() { "FS Support".to_owned() } else { app_name };
    if !app_name.is_empty() && crate::get_app_name() == "RustDesk" {
        *hbb_common::config::APP_NAME.write().unwrap() = app_name;
    }

    let host = build_value(option_env!("FS_RUSTDESK_HOST"));
    let key = build_value(option_env!("FS_RUSTDESK_KEY"));
    if host.is_empty() || key.is_empty() {
        return;
    }

    if has_existing_server_config() {
        return;
    }

    set_option_if_present("custom-rendezvous-server", &host);
    set_option_if_present("rendezvous-servers", &host);
    set_option_if_present("key", &key);
    set_option_if_present("relay-server", &build_value(option_env!("FS_RUSTDESK_RELAY")));
    set_option_if_present("api-server", &build_value(option_env!("FS_RUSTDESK_API")));
    set_option_if_present("fs-support-prefill-version", FS_SUPPORT_PREFILL_VERSION);
    log::info!("FS Support default RustDesk server configuration applied.");
}

pub fn display_version() -> String {
    let base = build_value(option_env!("FS_SUPPORT_BASE_VERSION"));
    if base.is_empty() {
        DEFAULT_FS_SUPPORT_VERSION.to_owned()
    } else {
        base
    }
}

pub fn product_version() -> String {
    if crate::common::is_custom_client() {
        display_version()
    } else {
        crate::VERSION.to_owned()
    }
}

pub fn windows_install_version() -> String {
    product_version().replace("-", ".")
}

pub fn windows_install_version_parts() -> Vec<String> {
    windows_install_version()
        .split('.')
        .map(|part| part.trim().to_owned())
        .collect()
}

// ---------------------------------------------------------------------------
// Mise à jour automatique FS Support (07/10/2026).
//
// Un client FS Support n'interroge jamais api.rustdesk.com : il demande la dernière version
// publiée (release GitHub `fs-nightly`, relayée par le SaaS) à api.fs-solutions.fr, qui répond
// `{ "version": "1.0.104", "url": "<lien de téléchargement direct>" }`.
// L'URL reçue est un lien direct vers le fichier (pas une page GitHub « releases/tag/x ») :
// la version et le nom du fichier local se déduisent donc d'ici, jamais de l'URL.
// ---------------------------------------------------------------------------

/// Point d'entrée de la vérification de version côté SaaS.
pub const UPDATE_CHECK_URL: &str = "https://api.fs-solutions.fr/public/support/rustdesk-version";

/// Seules les URLs de téléchargement servies par FS Solutions sont acceptées.
const UPDATE_DOWNLOAD_URL_PREFIX: &str = "https://api.fs-solutions.fr/";

lazy_static::lazy_static! {
    /// Dernière version proposée par api.fs-solutions.fr (vide si aucune mise à jour).
    static ref LATEST_UPDATE_VERSION: std::sync::Mutex<String> = Default::default();
}

/// Plateforme transmise au SaaS : windows, macos, android (linux/ios ne sont pas distribués).
pub fn update_platform() -> &'static str {
    std::env::consts::OS
}

/// Architecture transmise au SaaS : x86_64, aarch64, arm, x86.
pub fn update_arch() -> &'static str {
    std::env::consts::ARCH
}

/// Construit l'URL de vérification, paramètres encodés.
pub fn update_check_url() -> String {
    let current = product_version();
    match url::Url::parse_with_params(
        UPDATE_CHECK_URL,
        &[
            ("platform", update_platform()),
            ("arch", update_arch()),
            ("version", current.as_str()),
        ],
    ) {
        Ok(u) => u.to_string(),
        Err(_) => UPDATE_CHECK_URL.to_owned(),
    }
}

/// Version au format x.y.z (chiffres uniquement), comme attendu par `get_version_number`.
pub fn is_valid_update_version(version: &str) -> bool {
    let parts: Vec<&str> = version.split('.').collect();
    (parts.len() == 3 || parts.len() == 4)
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.len() <= 9 && p.chars().all(|c| c.is_ascii_digit()))
}

/// L'URL de téléchargement doit être en HTTPS chez FS Solutions.
pub fn is_valid_update_url(url: &str) -> bool {
    url.starts_with(UPDATE_DOWNLOAD_URL_PREFIX)
        && url.len() <= 2048
        && !url.chars().any(|c| c.is_whitespace() || c.is_control())
}

pub fn set_latest_update_version(version: &str) {
    *LATEST_UPDATE_VERSION.lock().unwrap() = version.to_owned();
}

pub fn latest_update_version() -> String {
    LATEST_UPDATE_VERSION.lock().unwrap().clone()
}

#[allow(dead_code)] // utilisé seulement sur Windows/macOS (updater)
/// Nom du fichier téléchargé dans le dossier temporaire, d'après la version proposée
/// (l'URL FS se termine par `/download?token=…`, inutilisable comme nom de fichier).
/// Windows : `.exe` obligatoire pour `update_to` ; macOS : `.dmg` pour `extract_update_dmg`.
pub fn update_file_name() -> Option<String> {
    let version = latest_update_version();
    if !is_valid_update_version(&version) {
        return None;
    }
    if cfg!(target_os = "windows") {
        // RustDesk 1.5.0 gère aussi Windows ARM64 : même suffixe que release_arch_suffix().
        if cfg!(target_arch = "aarch64") {
            Some(format!("fs-support-{version}-windows-aarch64.exe"))
        } else {
            Some(format!("fs-support-{version}-windows-x86_64.exe"))
        }
    } else if cfg!(target_os = "macos") {
        if cfg!(target_arch = "aarch64") {
            Some(format!("fs-support-{version}-macos-aarch64.dmg"))
        } else {
            Some(format!("fs-support-{version}-macos-x86_64.dmg"))
        }
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_de_mise_a_jour() {
        assert!(is_valid_update_version("1.0.104"));
        assert!(is_valid_update_version("1.0.104.2"));
        assert!(!is_valid_update_version("1.0"));
        assert!(!is_valid_update_version("1.0.x"));
        assert!(!is_valid_update_version("download"));
        assert!(!is_valid_update_version(""));
    }

    #[test]
    fn urls_de_mise_a_jour() {
        assert!(is_valid_update_url(
            "https://api.fs-solutions.fr/public/support/rustdesk-downloads/windows-exe/download?token=a.b"
        ));
        assert!(!is_valid_update_url("http://api.fs-solutions.fr/x"));
        assert!(!is_valid_update_url("https://api.fs-solutions.fr.evil.test/x"));
        assert!(!is_valid_update_url("https://github.com/rustdesk/rustdesk/releases/tag/1.4.6"));
    }
}
