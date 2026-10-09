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
// Schéma d'URL et extension de fichier (09/10/2026).
//
// Le nom de l'application, « FS Support », contient une espace. Il reste tel quel pour le
// dossier d'installation, l'exe, le service et %APPDATA%\FS Support (ID, mots de passe et
// réglages des clients en dépendent). Mais un schéma d'URL ne peut pas contenir d'espace
// (RFC 3986) : liens, extension `.<schéma>` et clés HKEY_CLASSES_ROOT utilisent donc une forme
// unique, en minuscules, chaque suite d'espaces remplacée par un tiret. « RustDesk » donne
// toujours « rustdesk ».
// ---------------------------------------------------------------------------

/// Forme sans espace d'un nom d'application : « FS Support » → « fs-support ».
pub fn url_scheme_of(app_name: &str) -> String {
    app_name
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join("-")
}

/// Schéma d'URL (`fs-support://`) et extension de fichier (`.fs-support`) du client.
pub fn url_scheme() -> String {
    url_scheme_of(&crate::get_app_name())
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

// ---------------------------------------------------------------------------
// Réglages de l'Atelier (09/10/2026).
//
// Les entreprises de l'accueil (`fs-company-*`, `fs-group-by-company`) étaient rangées dans les
// options Flutter de `<application>_local.toml`. Or `LocalConfig` (hbb_common) lit ce fichier une
// seule fois, au démarrage de chaque processus, et CHAQUE écriture le réenregistre en entier depuis
// cette copie en mémoire. Un autre processus FS Support lancé avant le changement (gestionnaire de
// connexions, page d'installation, ancienne version encore ouverte, barre des tâches…) qui
// enregistre ensuite n'importe quel réglage local (position de fenêtre, dernier ID…) efface donc
// les entreprises ajoutées entre-temps.
//
// Ces réglages ont désormais leur propre fichier, `<application>_atelier.json` à côté des autres,
// relu à chaque lecture et à chaque écriture ; seule la clé modifiée change, et le fichier est
// remplacé d'un bloc (écriture dans un fichier temporaire puis renommage). Une valeur vide y est
// gardée : sinon l'ancienne valeur de `_local.toml`, lue en repli tant que la clé n'a jamais été
// écrite ici (reprise des réglages existants), reviendrait.
// ---------------------------------------------------------------------------

/// Préfixe des clés de l'Atelier passées par `main_get_common` / `main_set_common`.
pub const ATELIER_OPTION_PREFIX: &str = "fs-atelier:";

lazy_static::lazy_static! {
    /// Lecture-modification-écriture du fichier sans chevauchement dans un même processus.
    static ref ATELIER_LOCK: std::sync::Mutex<()> = Default::default();
}

/// Clés acceptées : `fs-…`, lettres, chiffres et tirets.
fn is_atelier_key(k: &str) -> bool {
    k.starts_with("fs-")
        && k.len() <= 64
        && k.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

fn atelier_file() -> std::path::PathBuf {
    Config::path(format!("{}_atelier.json", crate::get_app_name()))
}

fn read_atelier_options(path: &std::path::Path) -> std::collections::BTreeMap<String, String> {
    match std::fs::read_to_string(path) {
        Ok(content) => serde_json::from_str(&content).unwrap_or_else(|e| {
            log::warn!("Réglages de l'Atelier illisibles ({}) : {}", path.display(), e);
            Default::default()
        }),
        Err(_) => Default::default(),
    }
}

fn write_atelier_options(
    path: &std::path::Path,
    options: &std::collections::BTreeMap<String, String>,
) -> std::io::Result<()> {
    let content = serde_json::to_string_pretty(options)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension(format!("json.{}.tmp", std::process::id()));
    std::fs::write(&tmp, content)?;
    std::fs::rename(&tmp, path).map_err(|e| {
        std::fs::remove_file(&tmp).ok();
        e
    })
}

fn get_atelier_option_in(path: &std::path::Path, k: &str) -> Option<String> {
    read_atelier_options(path).get(k).cloned()
}

fn set_atelier_option_in(path: &std::path::Path, k: &str, v: &str) -> std::io::Result<()> {
    let _guard = ATELIER_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut options = read_atelier_options(path);
    if options.get(k).map(String::as_str) == Some(v) {
        return Ok(());
    }
    options.insert(k.to_owned(), v.to_owned());
    write_atelier_options(path, &options)
}

/// Valeur d'un réglage de l'Atelier ; à défaut, ancienne valeur de `_local.toml`.
pub fn get_atelier_option(k: &str) -> String {
    if !is_atelier_key(k) {
        return String::new();
    }
    get_atelier_option_in(&atelier_file(), k)
        .unwrap_or_else(|| hbb_common::config::LocalConfig::get_flutter_option(k))
}

pub fn set_atelier_option(k: &str, v: &str) {
    if !is_atelier_key(k) {
        log::warn!("Réglage de l'Atelier refusé : {:?}", k);
        return;
    }
    if let Err(e) = set_atelier_option_in(&atelier_file(), k, v) {
        log::error!("Réglage de l'Atelier {} non enregistré : {}", k, e);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fs_atelier_cles_acceptees() {
        assert!(is_atelier_key("fs-company-map"));
        assert!(is_atelier_key("fs-group-by-company"));
        assert!(!is_atelier_key("company-map"));
        assert!(!is_atelier_key("fs-../x"));
        assert!(!is_atelier_key("fs-a b"));
        assert!(!is_atelier_key(""));
    }

    #[test]
    fn fs_atelier_seule_la_cle_modifiee_change() {
        let dir = std::env::temp_dir().join(format!("fs-atelier-test-{}", std::process::id()));
        let path = dir.join("FS Support_atelier.json");
        std::fs::remove_dir_all(&dir).ok();
        assert_eq!(get_atelier_option_in(&path, "fs-company-map"), None);

        set_atelier_option_in(&path, "fs-company-map", r#"{"123":"ACME"}"#).unwrap();
        set_atelier_option_in(&path, "fs-company-list", r#"["ACME"]"#).unwrap();
        // Un autre processus a ajouté une clé entre-temps : elle survit à l'écriture suivante.
        let mut on_disk = read_atelier_options(&path);
        on_disk.insert("fs-company-collapsed".to_owned(), r#"["acme"]"#.to_owned());
        write_atelier_options(&path, &on_disk).unwrap();
        set_atelier_option_in(&path, "fs-company-list", r#"["ACME","Durand"]"#).unwrap();

        assert_eq!(
            get_atelier_option_in(&path, "fs-company-map").as_deref(),
            Some(r#"{"123":"ACME"}"#)
        );
        assert_eq!(
            get_atelier_option_in(&path, "fs-company-collapsed").as_deref(),
            Some(r#"["acme"]"#)
        );
        assert_eq!(
            get_atelier_option_in(&path, "fs-company-list").as_deref(),
            Some(r#"["ACME","Durand"]"#)
        );
        // Effacer garde la clé (vide) : l'ancienne valeur de `_local.toml` ne revient pas.
        set_atelier_option_in(&path, "fs-company-map", "").unwrap();
        assert_eq!(get_atelier_option_in(&path, "fs-company-map").as_deref(), Some(""));
        // Pas de fichier temporaire laissé derrière.
        let leftovers = std::fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
            .count();
        assert_eq!(leftovers, 0);
        std::fs::remove_dir_all(&dir).ok();
    }

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
    fn nom_app_schema_url_sans_espace() {
        assert_eq!(url_scheme_of("FS Support"), "fs-support");
        assert_eq!(url_scheme_of("RustDesk"), "rustdesk");
        assert_eq!(url_scheme_of("FS-Solutions Support 2"), "fs-solutions-support-2");
        assert_eq!(url_scheme_of(" FS   Support "), "fs-support");
        // Le lien construit avec ce schéma est une URL valide.
        let link = format!("{}://123456789", url_scheme_of("FS Support"));
        let parsed = url::Url::parse(&link).expect("le lien doit être une URL valide");
        assert_eq!(parsed.scheme(), "fs-support");
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
