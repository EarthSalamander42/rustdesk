// FS Support — noms launchd et installation du service macOS (20/10/2026).
//
// Constat (Mac Intel de Jason, macOS 12.7.6) : la carte « Installer » ne faisait rien. RustDesk
// construit les noms du service à partir du nom de l'application : `com.carriez.<APP>_service` et
// `com.carriez.<APP>_server`. Avec « FS Support », l'espace se retrouvait dans les étiquettes launchd
// et dans des chemins non protégés des scripts d'installation (`echo … > /Library/LaunchDaemons/
// com.carriez.FS Support_service.plist` écrit en réalité dans `com.carriez.FS`), et l'échec était
// avalé sans message. Même famille de panne que l'installeur Windows (PR #10).
//
// Ce module ne fait que des calculs (aucun appel système) : il est compilé et testé partout,
// y compris dans l'étape Windows de la CI (`cargo test fs_mac_service::`).

/// Identifiant launchd de FS Support : sans espace, stable, propre à FS Solutions.
pub const FS_LAUNCHD_PREFIX: &str = "fr.fs-solutions.support";

/// Option locale qui porte l'état de la dernière installation du service, lue par l'interface.
/// Valeurs : "" (rien), "en-cours", "ok", "erreur:<message en français>".
pub const INSTALL_STATUS_OPTION: &str = "fs-mac-service-install";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LaunchdNames {
    pub daemon_label: String,
    pub agent_label: String,
    pub daemon_plist: String,
    pub agent_plist: String,
}

impl LaunchdNames {
    pub fn from_prefix(prefix: &str) -> Self {
        let daemon_label = format!("{}_service", prefix);
        let agent_label = format!("{}_server", prefix);
        Self {
            daemon_plist: format!("/Library/LaunchDaemons/{}.plist", daemon_label),
            agent_plist: format!("/Library/LaunchAgents/{}.plist", agent_label),
            daemon_label,
            agent_label,
        }
    }
}

/// Garde lettres, chiffres, `.`, `-` et `_` ; tout le reste (espace compris) devient `-`.
pub fn sanitize_launchd(s: &str) -> String {
    s.chars()
        .map(|c| if c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_') { c } else { '-' })
        .collect()
}

/// Préfixe launchd : RustDesk d'origine inchangé (`com.carriez.RustDesk`), FS Support =
/// `fr.fs-solutions.support`, tout autre nom = nom complet assaini.
pub fn launchd_prefix(org: &str, app_name: &str) -> String {
    if app_name == "RustDesk" {
        format!("{}.{}", org, app_name)
    } else if app_name.trim().eq_ignore_ascii_case("FS Support") {
        FS_LAUNCHD_PREFIX.to_owned()
    } else {
        sanitize_launchd(&format!("{}.{}", org, app_name))
    }
}

pub fn launchd_names(org: &str, app_name: &str) -> LaunchdNames {
    LaunchdNames::from_prefix(&launchd_prefix(org, app_name))
}

/// Anciens noms (ceux de RustDesk, `<org>.<APP>`), à nettoyer à l'installation et à la
/// désinstallation. Inclut la forme tronquée à la première espace qu'écrivait l'ancien script
/// (`com.carriez.FS`), seulement si elle diffère du nouveau nom.
pub fn legacy_launchd_names(org: &str, app_name: &str) -> Vec<LaunchdNames> {
    let current = launchd_names(org, app_name);
    let full = format!("{}.{}", org, app_name);
    let mut out: Vec<LaunchdNames> = Vec::new();
    let mut push = |n: LaunchdNames| {
        if n != current && !out.contains(&n) {
            out.push(n);
        }
    };
    push(LaunchdNames::from_prefix(&full));
    if let Some((tronque, _)) = full.split_once(' ') {
        // L'ancien `echo … > /Library/LaunchDaemons/com.carriez.FS Support_service.plist` créait
        // le fichier `/Library/LaunchDaemons/com.carriez.FS` (sans extension).
        push(LaunchdNames {
            daemon_label: tronque.to_owned(),
            agent_label: tronque.to_owned(),
            daemon_plist: format!("/Library/LaunchDaemons/{}", tronque),
            agent_plist: format!("/Library/LaunchAgents/{}", tronque),
        });
    }
    out
}

/// Entrées « étiquette|chemin » transmises aux scripts d'installation pour le nettoyage.
pub fn legacy_entries(org: &str, app_name: &str) -> Vec<String> {
    let mut v = Vec::new();
    for n in legacy_launchd_names(org, app_name) {
        v.push(format!("{}|{}", n.daemon_label, n.daemon_plist));
        v.push(format!("{}|{}", n.agent_label, n.agent_plist));
    }
    v
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// Remplit un modèle de plist (`daemon.plist` / `agent.plist`) : étiquettes, chemins de l'app,
/// identifiant de bundle et journaux. Les valeurs sont échappées pour le XML.
pub fn render_plist(template: &str, names: &LaunchdNames, app_name: &str, bundle_id: &str) -> String {
    let app_bundle = format!("/Applications/{}.app", app_name);
    let log_base = format!("/var/log/{}", sanitize_launchd(&app_name.to_lowercase()));
    template
        .replace('\r', "")
        .replace("{{DAEMON_LABEL}}", &xml_escape(&names.daemon_label))
        .replace("{{AGENT_LABEL}}", &xml_escape(&names.agent_label))
        .replace("{{APP_BUNDLE}}", &xml_escape(&app_bundle))
        .replace("{{APP_EXE}}", &xml_escape(&format!("{}/Contents/MacOS/{}", app_bundle, app_name)))
        // Passé à `/bin/sh -c` : entre apostrophes pour que l'espace du nom ne coupe pas la commande.
        .replace(
            "{{SERVICE_CMD}}",
            &xml_escape(&format!("'{}/Contents/MacOS/service'", app_bundle.replace('\'', "'\\''"))),
        )
        .replace("{{BUNDLE_ID}}", &xml_escape(bundle_id))
        .replace("{{LOG_BASE}}", &xml_escape(&log_base))
}

/// Message français affiché à l'utilisateur à partir de la sortie d'erreur d'osascript.
pub fn french_install_error(stderr: &str, code: Option<i32>) -> String {
    if stderr.contains("(-128)") {
        return "Installation annulée : le mot de passe administrateur n'a pas été saisi.".to_owned();
    }
    let detail = stderr
        .lines()
        .find_map(|l| l.split_once("FS-ERREUR:").map(|(_, m)| m.trim().to_owned()))
        .or_else(|| stderr.lines().map(str::trim).find(|l| !l.is_empty()).map(str::to_owned))
        .unwrap_or_else(|| match code {
            Some(c) => format!("code de sortie {}", c),
            None => "cause inconnue".to_owned(),
        });
    format!("Installation du service FS Support impossible : {}", detail)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fs_support_sans_espace() {
        let n = launchd_names("com.carriez", "FS Support");
        assert_eq!(n.daemon_label, "fr.fs-solutions.support_service");
        assert_eq!(n.agent_label, "fr.fs-solutions.support_server");
        assert_eq!(n.daemon_plist, "/Library/LaunchDaemons/fr.fs-solutions.support_service.plist");
        assert_eq!(n.agent_plist, "/Library/LaunchAgents/fr.fs-solutions.support_server.plist");
        for s in [&n.daemon_label, &n.agent_label, &n.daemon_plist, &n.agent_plist] {
            assert!(!s.contains(' '), "{}", s);
        }
    }

    #[test]
    fn rustdesk_inchange() {
        let n = launchd_names("com.carriez", "RustDesk");
        assert_eq!(n.daemon_label, "com.carriez.RustDesk_service");
        assert_eq!(n.agent_plist, "/Library/LaunchAgents/com.carriez.RustDesk_server.plist");
        assert!(legacy_launchd_names("com.carriez", "RustDesk").is_empty());
    }

    #[test]
    fn autre_nom_assaini() {
        let n = launchd_names("com.acme", "Mon Appli/2");
        assert_eq!(n.daemon_label, "com.acme.Mon-Appli-2_service");
    }

    #[test]
    fn anciens_noms_a_nettoyer() {
        let e = legacy_entries("com.carriez", "FS Support");
        assert!(e.contains(&"com.carriez.FS Support_service|/Library/LaunchDaemons/com.carriez.FS Support_service.plist".to_owned()));
        assert!(e.contains(&"com.carriez.FS Support_server|/Library/LaunchAgents/com.carriez.FS Support_server.plist".to_owned()));
        assert!(e.contains(&"com.carriez.FS|/Library/LaunchDaemons/com.carriez.FS".to_owned()));
        assert!(e.contains(&"com.carriez.FS|/Library/LaunchAgents/com.carriez.FS".to_owned()));
        assert_eq!(e.len(), 4);
    }

    #[test]
    fn modeles_remplis_et_valides() {
        let n = launchd_names("com.carriez", "FS Support");
        let agent = render_plist(include_str!("platform/privileges_scripts/agent.plist"), &n, "FS Support", "com.carriez.flutterHbb");
        assert!(agent.contains("<string>fr.fs-solutions.support_server</string>"));
        assert!(agent.contains("<string>/Applications/FS Support.app/Contents/MacOS/FS Support</string>"));
        assert!(!agent.contains("{{"));
        let daemon = render_plist(include_str!("platform/privileges_scripts/daemon.plist"), &n, "FS Support", "com.carriez.flutterHbb");
        assert!(daemon.contains("<string>fr.fs-solutions.support_service</string>"));
        assert!(daemon.contains("<string>'/Applications/FS Support.app/Contents/MacOS/service'</string>"));
        assert!(daemon.contains("/var/log/fs-support_service.err"));
        assert!(!daemon.contains("{{"));
        assert!(!daemon.contains('\r'));
    }

    #[test]
    fn messages_francais() {
        assert!(french_install_error("0:120: execution error: User canceled. (-128)", Some(1)).contains("annulée"));
        assert_eq!(
            french_install_error("x\nFS-ERREUR: launchctl refuse le service\n", Some(1)),
            "Installation du service FS Support impossible : launchctl refuse le service"
        );
        assert!(french_install_error("", Some(3)).contains("code de sortie 3"));
    }
}
