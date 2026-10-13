// ---------------------------------------------------------------------------
// Jeton d'enrôlement FS Support (13/10/2026).
//
// Le CRM de FS Full Flux génère, depuis la fiche d'un client (ou d'un équipement de son parc),
// un jeton opaque : 26 caractères aléatoires, à usage limité et daté, dont le SaaS ne garde que
// l'empreinte. Le jeton n'ouvre AUCUN accès au poste ni au SaaS : il dit seulement « range ce
// poste chez tel client » la première fois qu'il est présenté.
//
// Il arrive sur le poste par deux chemins :
//   (a) le nom du fichier téléchargé (Windows) :
//         fs-support-1.0.110-windows-x86_64,enrol=<jeton>,.exe
//       même convention « clé=valeur » séparées par des virgules que celle de RustDesk pour
//       `host=…,key=…` (src/custom_server.rs) ; la virgule finale protège le jeton du « (1) »
//       que Windows ajoute aux doublons. L'enveloppe portable (libs/portable) transmet le nom
//       d'origine dans RUSTDESK_APPNAME ;
//   (b) un lien `fs-support://enrol?t=<jeton>` ouvert sur un poste où FS Support est déjà installé
//       (Windows : traité dans core_main avant l'interface ; macOS/Android : par Flutter, qui
//       appelle main_set_common("fs-enrolment-uri", …)).
//
// Le jeton est rangé dans la config (option `fs-enrolment-token`, transmise au service par l'IPC
// comme n'importe quel réglage), envoyé dans le sysinfo (champ `fs_enrolment_token`) jusqu'à ce
// que le SaaS réponde SYSINFO_UPDATED, puis effacé. L'empreinte du dernier jeton confirmé
// (`fs-enrolment-done`) empêche de le renvoyer si une copie périmée des réglages le réécrit.
// Le jeton n'apparaît jamais dans les journaux : seulement son empreinte courte.
// ---------------------------------------------------------------------------

#![allow(dead_code)] // selon la plateforme, une partie seulement de ces fonctions sert

use hbb_common::{config::Config, log};

/// Jeton en attente d'envoi.
pub const OPTION_TOKEN: &str = "fs-enrolment-token";
/// Empreinte du dernier jeton confirmé par le SaaS (jamais le jeton lui-même).
pub const OPTION_DONE: &str = "fs-enrolment-done";
/// Champ ajouté au sysinfo envoyé à l'api-server.
pub const SYSINFO_FIELD: &str = "fs_enrolment_token";
/// Clé passée par Flutter à `main_set_common` pour un lien reçu (macOS, Android).
pub const COMMON_KEY_URI: &str = "fs-enrolment-uri";

const FILE_NAME_KEY: &str = "enrol=";
const URI_HOST: &str = "enrol";
const URI_QUERY_KEY: &str = "t";
const MIN_LEN: usize = 16;
const MAX_LEN: usize = 64;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum StoreResult {
    /// Rangé (ou déjà en attente) : il partira avec le prochain sysinfo.
    Stored,
    /// Déjà confirmé par le SaaS : rien à faire.
    AlreadyDone,
    /// Forme invalide : ignoré.
    Invalid,
}

fn is_token_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '-' || c == '_'
}

/// Forme acceptée côté client : 16 à 64 caractères `[A-Za-z0-9_-]`. Le SaaS émet aujourd'hui
/// 26 caractères base32 en minuscules ; la marge laisse le format évoluer sans nouveau client.
pub fn is_valid_token(token: &str) -> bool {
    (MIN_LEN..=MAX_LEN).contains(&token.len()) && token.chars().all(is_token_char)
}

/// Empreinte courte (16 caractères hexadécimaux du SHA-256) : journaux et `fs-enrolment-done`.
pub fn fingerprint(token: &str) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(token.as_bytes())
        .iter()
        .take(8)
        .map(|b| format!("{:02x}", b))
        .collect()
}

/// Jeton contenu dans un nom de fichier : `…,enrol=<jeton>,.exe` (virgule finale facultative).
/// Seul le nom compte, jamais les dossiers ; une suite non conforme est ignorée.
pub fn token_from_file_name(name: &str) -> Option<String> {
    let name = name.rsplit(|c| c == '\\' || c == '/').next().unwrap_or(name);
    for part in name.split(',') {
        let part = part.trim_start();
        // `get` plutôt qu'un découpage direct : un nom accentué ne doit jamais faire paniquer.
        match part.get(..FILE_NAME_KEY.len()) {
            Some(key) if key.eq_ignore_ascii_case(FILE_NAME_KEY) => {}
            _ => continue,
        }
        // Jusqu'au premier caractère étranger : « .exe », « (1).exe », espace…
        let token: String = part[FILE_NAME_KEY.len()..]
            .chars()
            .take_while(|c| is_token_char(*c))
            .collect();
        if is_valid_token(&token) {
            return Some(token);
        }
    }
    None
}

/// Le lien est-il un lien d'enrôlement (`<schéma>://enrol…`), valide ou non ?
pub fn is_enrol_uri(uri: &str) -> bool {
    let prefix = crate::get_uri_prefix();
    let rest = match uri.get(..prefix.len()) {
        Some(head) if head.eq_ignore_ascii_case(&prefix) => &uri[prefix.len()..],
        _ => return false,
    };
    match rest.get(..URI_HOST.len()) {
        Some(host) if host.eq_ignore_ascii_case(URI_HOST) => rest[URI_HOST.len()..]
            .chars()
            .next()
            .map_or(true, |c| c == '?' || c == '/'),
        _ => false,
    }
}

/// Jeton d'un lien `fs-support://enrol?t=<jeton>` (ou `fs-support://enrol/<jeton>`).
pub fn token_from_uri(uri: &str) -> Option<String> {
    if !is_enrol_uri(uri) {
        return None;
    }
    let parsed = url::Url::parse(uri).ok()?;
    let from_query = parsed
        .query_pairs()
        .find(|(k, _)| k == URI_QUERY_KEY)
        .map(|(_, v)| v.into_owned());
    let token = from_query.or_else(|| {
        parsed
            .path_segments()
            .and_then(|mut segments| segments.find(|s| !s.is_empty()).map(|s| s.to_owned()))
    })?;
    if is_valid_token(&token) {
        Some(token)
    } else {
        None
    }
}

/// Jeton à envoyer avec le prochain sysinfo (processus qui tient la config : service ou portable).
pub fn pending_token() -> Option<String> {
    let token = Config::get_option(OPTION_TOKEN);
    if !is_valid_token(&token) {
        return None;
    }
    if Config::get_option(OPTION_DONE) == fingerprint(&token) {
        return None;
    }
    Some(token)
}

/// Le SaaS a répondu SYSINFO_UPDATED à un sysinfo portant `sent` : on l'efface et on garde son empreinte.
pub fn confirm_sent(sent: &str) {
    if Config::get_option(OPTION_TOKEN) == sent {
        Config::set_option(OPTION_TOKEN.to_owned(), "".to_owned());
    }
    Config::set_option(OPTION_DONE.to_owned(), fingerprint(sent));
    log::info!(
        "FS Support : jeton d'enrôlement {} pris en compte par le SaaS, effacé du poste",
        fingerprint(sent)
    );
}

/// Range un jeton. Sur ordinateur, il passe par l'IPC du service s'il tourne (c'est le service
/// qui envoie le sysinfo) et dans la config locale dans tous les cas (copie portable, et reprise
/// par `--import-config` à l'installation).
pub fn store_token(token: &str) -> StoreResult {
    if !is_valid_token(token) {
        return StoreResult::Invalid;
    }
    let done = fingerprint(token);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let options = crate::ipc::get_options();
        if options.get(OPTION_DONE) == Some(&done) {
            return StoreResult::AlreadyDone;
        }
        if options.get(OPTION_TOKEN).map(String::as_str) != Some(token) {
            crate::ipc::set_option(OPTION_TOKEN, token);
        }
    }
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        if Config::get_option(OPTION_DONE) == done {
            return StoreResult::AlreadyDone;
        }
        Config::set_option(OPTION_TOKEN.to_owned(), token.to_owned());
    }
    log::info!("FS Support : jeton d'enrôlement {} rangé", done);
    StoreResult::Stored
}

fn message_for(result: Option<StoreResult>) -> &'static str {
    match result {
        Some(StoreResult::Stored) => {
            "Lien reçu : ce poste va être relié à votre dossier client dans quelques instants."
        }
        Some(StoreResult::AlreadyDone) => "Ce poste est déjà relié à votre dossier client.",
        _ => "Ce lien FS Support n'est pas valide. Demandez-en un nouveau à votre prestataire.",
    }
}

/// Lien `fs-support://enrol?t=…` reçu par un processus (Windows : argument de la ligne de commande ;
/// macOS/Android : relayé par Flutter). Renvoie le message à montrer à l'utilisateur.
pub fn handle_enrol_uri(uri: &str) -> &'static str {
    let result = token_from_uri(uri).map(|t| store_token(&t));
    if result.is_none() {
        log::warn!("FS Support : lien d'enrôlement invalide reçu");
    }
    let message = message_for(result);
    #[cfg(windows)]
    show_toast(message);
    message
}

/// Windows : jeton porté par le nom de l'exécutable téléchargé (première ouverture, avant ou pendant
/// l'installation). Sans effet si le nom n'en porte pas.
#[cfg(windows)]
pub fn capture_from_exe_name() {
    let name = std::env::var(crate::common::PORTABLE_APPNAME_RUNTIME_ENV_KEY)
        .ok()
        .filter(|n| !n.is_empty())
        .or_else(|| {
            std::env::current_exe()
                .ok()
                .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
        });
    let Some(token) = name.as_deref().and_then(token_from_file_name) else {
        return;
    };
    match store_token(&token) {
        StoreResult::Stored => {}
        StoreResult::AlreadyDone => log::info!(
            "FS Support : jeton d'enrôlement {} du nom de fichier déjà pris en compte",
            fingerprint(&token)
        ),
        StoreResult::Invalid => {}
    }
}

#[cfg(windows)]
fn show_toast(message: &str) {
    use tauri_winrt_notification::{Duration, Sound, Toast};
    Toast::new(Toast::POWERSHELL_APP_ID)
        .title(&crate::get_app_name())
        .text1(message)
        .sound(Some(Sound::Default))
        .duration(Duration::Short)
        .show()
        .ok();
}

#[cfg(test)]
mod tests {
    use super::*;

    const T: &str = "abcdefghijklmnopqrstuvwxyz";

    #[test]
    fn forme_du_jeton() {
        assert!(is_valid_token(T));
        assert!(is_valid_token("ABC_def-0123456789"));
        assert!(!is_valid_token("court"));
        assert!(!is_valid_token(&"a".repeat(65)));
        assert!(!is_valid_token("abcdefghijklmnop qrst"));
        assert!(!is_valid_token("abcdefghijklmnop,qrst"));
        assert!(!is_valid_token("abcdefghijklmnop%2Cqrst"));
    }

    #[test]
    fn jeton_dans_le_nom_du_fichier() {
        let attendu = Some(T.to_owned());
        assert_eq!(
            token_from_file_name(&format!("fs-support-1.0.110-windows-x86_64,enrol={T},.exe")),
            attendu
        );
        // Doublon renommé par le navigateur ou l'Explorateur.
        assert_eq!(
            token_from_file_name(&format!("fs-support-1.0.110-windows-x86_64,enrol={T}, (1).exe")),
            attendu
        );
        // Sans virgule finale.
        assert_eq!(token_from_file_name(&format!("fs-support,enrol={T}.exe")), attendu);
        assert_eq!(token_from_file_name(&format!("fs-support,enrol={T}.exe.exe")), attendu);
        // Casse de la clé indifférente, chemin complet accepté (seul le nom compte).
        assert_eq!(
            token_from_file_name(&format!("C:\\Users\\x\\Downloads\\fs-support,ENROL={T},.exe")),
            attendu
        );
        // Combinable avec la convention RustDesk host=/key=.
        assert_eq!(
            token_from_file_name(&format!("rustdesk-host=rd.example.net,key=abc,enrol={T},.exe")),
            attendu
        );
        assert_eq!(token_from_file_name("fs-support-1.0.110-windows-x86_64.exe"), None);
        assert_eq!(token_from_file_name("fs-support,enrol=court,.exe"), None);
        assert_eq!(token_from_file_name(&format!("fs-support-enrol={T}.exe")), None);
        // Nom accentué : jamais de panique.
        assert_eq!(token_from_file_name("é,é,ée=x,.exe"), None);
        // Un dossier nommé comme un jeton ne compte pas.
        assert_eq!(token_from_file_name(&format!("C:\\x,enrol={T},\\fs-support.exe")), None);
    }

    #[test]
    fn le_nom_de_fichier_reste_lisible_par_custom_server() {
        // Le jeton ne doit pas perturber la lecture host=/key= de RustDesk…
        let lic = crate::custom_server::get_custom_server_from_string(&format!(
            "rustdesk-host=rd.example.net,key=abc,enrol={T},.exe"
        ))
        .unwrap();
        assert_eq!(lic.host, "rd.example.net");
        assert_eq!(lic.key, "abc");
        // … ni être pris pour une configuration quand il est seul.
        assert!(crate::custom_server::get_custom_server_from_string(&format!(
            "fs-support-1.0.110-windows-x86_64,enrol={T},.exe"
        ))
        .is_err());
    }

    #[test]
    fn jeton_dans_un_lien() {
        let p = crate::get_uri_prefix();
        let attendu = Some(T.to_owned());
        assert!(is_enrol_uri(&format!("{p}enrol?t={T}")));
        assert!(is_enrol_uri(&format!("{p}ENROL/?t={T}")));
        assert!(!is_enrol_uri(&format!("{p}enrollment?t={T}")));
        assert!(!is_enrol_uri(&format!("{p}connect/123456789")));
        assert!(!is_enrol_uri(&format!("https://enrol?t={T}")));
        assert!(!is_enrol_uri("é"));
        assert_eq!(token_from_uri(&format!("{p}enrol?t={T}")), attendu);
        assert_eq!(token_from_uri(&format!("{p}enrol/?t={T}")), attendu);
        assert_eq!(token_from_uri(&format!("{p}enrol/{T}")), attendu);
        assert_eq!(token_from_uri(&format!("{p}enrol?x=1&t={T}")), attendu);
        assert_eq!(token_from_uri(&format!("{p}enrol?t=court")), None);
        assert_eq!(token_from_uri(&format!("{p}enrol?t={T}%20")), None);
        assert_eq!(token_from_uri(&format!("{p}enrol")), None);
    }

    #[test]
    fn empreinte_courte_et_stable() {
        let f = fingerprint(T);
        assert_eq!(f.len(), 16);
        assert_eq!(f, fingerprint(T));
        assert_ne!(f, fingerprint("abcdefghijklmnopqrstuvwxyy"));
        assert!(!f.contains(T));
    }
}
