// FS Support : ménage des anciens dossiers d'extraction (09/10/2026).
//
// Chaque build se décompresse dans son propre dossier `app-<version>-<build>` (voir `main.rs`).
// Après le lancement, les autres dossiers `app-*` du même parent sont supprimés, ainsi que
// l'ancien dossier commun `%LOCALAPPDATA%\rustdesk` quand il porte la marque d'une extraction
// FS Support. Jamais le dossier en cours, jamais un dossier encore utilisé :
// 1. un dossier modifié depuis moins de deux minutes est peut-être en cours d'extraction ;
// 2. un `.exe` ou `.dll` qu'on ne peut pas ouvrir en accès exclusif est en cours d'exécution ;
// 3. le dossier est d'abord renommé (`~retire-…`) : Windows refuse de renommer un dossier dont
//    un fichier est ouvert, et plus personne ne peut lancer quoi que ce soit depuis le nouveau nom.
// Seul un dossier renommé est supprimé. Si la suppression échoue à mi-chemin, le reste est repris
// au lancement suivant. Liens symboliques et jonctions ne sont jamais suivis.
#![cfg_attr(not(windows), allow(dead_code))]

use std::{
    fs,
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};

use crate::{APP_METADATA_CONFIG, EXTRACTION_PREFIX, FS_LEGACY_MARKER};

/// Dossiers renommés, en attente de suppression.
const RETIRED_PREFIX: &str = "~retire-";

/// En dessous de cet âge, un dossier peut être en cours d'extraction par une autre copie.
const MIN_AGE: Duration = Duration::from_secs(120);

/// Supprime les extractions précédentes ; renvoie les dossiers effectivement retirés.
pub(crate) fn remove_old_extractions(current: &Path, legacy: &Path) -> Vec<PathBuf> {
    remove_old_extractions_with(current, legacy, MIN_AGE)
}

pub(crate) fn remove_old_extractions_with(
    current: &Path,
    legacy: &Path,
    min_age: Duration,
) -> Vec<PathBuf> {
    let mut removed = Vec::new();
    let (Some(root), Some(current_name)) = (current.parent(), current.file_name()) else {
        return removed;
    };
    let current_name = current_name.to_string_lossy().to_string();
    if let Ok(entries) = fs::read_dir(root) {
        for entry in entries.flatten() {
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            // `is_dir` est faux pour un lien symbolique ou une jonction.
            if !file_type.is_dir() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            if name.eq_ignore_ascii_case(&current_name) {
                continue;
            }
            let path = entry.path();
            if name.starts_with(RETIRED_PREFIX) {
                // Déjà renommé lors d'un passage précédent : plus rien ne s'y exécute.
                if fs::remove_dir_all(&path).is_ok() {
                    removed.push(path);
                }
            } else if starts_with_ignore_case(&name, EXTRACTION_PREFIX) {
                if retire(&path, root, min_age) {
                    removed.push(path);
                }
            }
        }
    }
    if is_fs_legacy_extraction(legacy) && retire(legacy, root, min_age) {
        removed.push(legacy.to_path_buf());
    }
    removed
}

fn starts_with_ignore_case(name: &str, prefix: &str) -> bool {
    name.len() >= prefix.len()
        && name.is_char_boundary(prefix.len())
        && name[..prefix.len()].eq_ignore_ascii_case(prefix)
}

/// Ancien dossier commun : vrai dossier (pas un lien), extrait par le paquet (`meta.toml`)
/// et contenant les ressources de l'habillage FS Support.
fn is_fs_legacy_extraction(dir: &Path) -> bool {
    let Ok(meta) = fs::symlink_metadata(dir) else {
        return false;
    };
    meta.is_dir()
        && dir.join(APP_METADATA_CONFIG).is_file()
        && dir.join(FS_LEGACY_MARKER).is_dir()
}

fn is_recent(dir: &Path, min_age: Duration) -> bool {
    if min_age.is_zero() {
        return false;
    }
    let Ok(modified) = fs::symlink_metadata(dir).and_then(|m| m.modified()) else {
        // Date illisible : prudence.
        return true;
    };
    match SystemTime::now().duration_since(modified) {
        Ok(age) => age < min_age,
        // Date dans le futur : prudence.
        Err(_) => true,
    }
}

/// Un exécutable ou une bibliothèque du dossier est-il ouvert (programme en cours) ?
#[cfg(windows)]
fn is_in_use(dir: &Path) -> bool {
    use std::os::windows::fs::OpenOptionsExt;
    let Ok(entries) = fs::read_dir(dir) else {
        return true;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let is_binary = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.eq_ignore_ascii_case("exe") || e.eq_ignore_ascii_case("dll"))
            .unwrap_or(false);
        if !is_binary || !entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
            continue;
        }
        // Accès en écriture sans aucun partage : refusé tant que le fichier est chargé ou ouvert.
        // Le fichier n'est ni tronqué ni modifié.
        if fs::OpenOptions::new()
            .write(true)
            .share_mode(0)
            .open(&path)
            .is_err()
        {
            return true;
        }
    }
    false
}

#[cfg(not(windows))]
fn is_in_use(_dir: &Path) -> bool {
    false
}

/// Renomme `dir` en `~retire-…` dans `root`, puis le supprime. Faux si le dossier est en service.
fn retire(dir: &Path, root: &Path, min_age: Duration) -> bool {
    if is_recent(dir, min_age) || is_in_use(dir) {
        return false;
    }
    let pid = std::process::id();
    let target = (0..100)
        .map(|n| root.join(format!("{}{}-{}", RETIRED_PREFIX, pid, n)))
        .find(|p| fs::symlink_metadata(p).is_err());
    let Some(target) = target else {
        return false;
    };
    if fs::rename(dir, &target).is_err() {
        return false;
    }
    // Un échec partiel est repris au prochain lancement (préfixe `~retire-`).
    let _ = fs::remove_dir_all(&target);
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TempRoot(PathBuf);

    impl TempRoot {
        fn new(name: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "fs-portable-{}-{}-{}",
                name,
                std::process::id(),
                SystemTime::now()
                    .duration_since(SystemTime::UNIX_EPOCH)
                    .map(|d| d.as_nanos())
                    .unwrap_or(0)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TempRoot {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn extraction(dir: &Path) {
        fs::create_dir_all(dir.join("data")).unwrap();
        fs::write(dir.join("FS Support.exe"), b"exe").unwrap();
        fs::write(dir.join("librustdesk.dll"), b"dll").unwrap();
        fs::write(dir.join("data").join("app.so"), b"so").unwrap();
        fs::write(dir.join(APP_METADATA_CONFIG), b"timestamp = 1\n").unwrap();
    }

    /// Ménage répété quelques secondes : un antivirus peut ouvrir brièvement les fichiers qui
    /// viennent d'être écrits, et le ménage attend alors, à raison, le passage suivant.
    fn clean_until(current: &Path, legacy: &Path, done: impl Fn() -> bool) -> Vec<PathBuf> {
        let mut removed = Vec::new();
        for _ in 0..40 {
            removed.extend(remove_old_extractions_with(current, legacy, Duration::ZERO));
            if done() {
                break;
            }
            std::thread::sleep(Duration::from_millis(250));
        }
        removed
    }

    #[test]
    fn fs_extraction_anciens_dossiers_supprimes() {
        let tmp = TempRoot::new("menage");
        let local = tmp.0.join("Local");
        let root = local.join("FS Support");
        let current = root.join("app-1.0.109-68e7a3c1");
        let old = root.join("app-1.0.108-68e00000");
        let leftover = root.join(format!("{}123-0", RETIRED_PREFIX));
        let other = root.join("journal");
        extraction(&current);
        extraction(&old);
        extraction(&leftover);
        fs::create_dir_all(&other).unwrap();
        fs::write(root.join("app-fichier.txt"), b"x").unwrap();

        let removed = clean_until(&current, &local.join("rustdesk"), || {
            !old.exists() && !leftover.exists()
        });

        assert!(current.join("FS Support.exe").is_file(), "le dossier en cours est intact");
        assert!(!old.exists(), "l'ancienne version est supprimée");
        assert!(!leftover.exists(), "un reste de suppression est repris");
        assert!(other.is_dir(), "un autre dossier n'est pas touché");
        assert!(root.join("app-fichier.txt").is_file(), "un fichier n'est pas touché");
        assert!(removed.contains(&old) && removed.contains(&leftover), "{:?}", removed);
        // Aucun dossier « ~retire- » ne reste derrière.
        let rest: Vec<String> = fs::read_dir(&root)
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().to_string())
            .collect();
        assert!(!rest.iter().any(|n| n.starts_with(RETIRED_PREFIX)), "{:?}", rest);
    }

    #[test]
    fn fs_extraction_dossier_recent_conserve() {
        let tmp = TempRoot::new("recent");
        let root = tmp.0.join("FS Support");
        let current = root.join("app-1.0.109-2");
        let other = root.join("app-1.0.109-1");
        extraction(&current);
        extraction(&other);
        // Peut-être en cours d'extraction par une autre copie : on attend.
        remove_old_extractions_with(&current, &tmp.0.join("rustdesk"), MIN_AGE);
        assert!(other.join("FS Support.exe").is_file());
    }

    #[test]
    fn fs_extraction_ancien_dossier_rustdesk() {
        let tmp = TempRoot::new("legacy");
        let root = tmp.0.join("FS Support");
        let current = root.join("app-1.0.109-1");
        extraction(&current);

        // RustDesk portable (sans l'habillage FS Support) : jamais touché.
        let legacy = tmp.0.join("rustdesk");
        extraction(&legacy);
        remove_old_extractions_with(&current, &legacy, Duration::ZERO);
        assert!(legacy.join("FS Support.exe").is_file());

        // Extraction FS Support : supprimée.
        fs::create_dir_all(legacy.join(FS_LEGACY_MARKER)).unwrap();
        let removed = clean_until(&current, &legacy, || !legacy.exists());
        assert!(!legacy.exists());
        assert!(removed.contains(&legacy), "{:?}", removed);
        assert!(current.join("FS Support.exe").is_file());
    }

    #[cfg(windows)]
    #[test]
    fn fs_extraction_dossier_en_service_conserve() {
        use std::os::windows::fs::OpenOptionsExt;
        const FILE_SHARE_READ: u32 = 1;
        let tmp = TempRoot::new("verrou");
        let root = tmp.0.join("FS Support");
        let current = root.join("app-1.0.109-2");
        let running = root.join("app-1.0.108-1");
        extraction(&current);
        extraction(&running);
        // Comme un exécutable en cours : ouvert, partagé en lecture seulement.
        let lock = fs::OpenOptions::new()
            .read(true)
            .share_mode(FILE_SHARE_READ)
            .open(running.join("FS Support.exe"))
            .unwrap();
        let removed = remove_old_extractions_with(&current, &tmp.0.join("rustdesk"), Duration::ZERO);
        assert!(removed.is_empty());
        assert!(running.join("FS Support.exe").is_file());
        assert!(running.join("data").join("app.so").is_file(), "rien n'est supprimé à moitié");
        drop(lock);
        // Une fois le programme fermé, le dossier part au lancement suivant.
        clean_until(&current, &tmp.0.join("rustdesk"), || !running.exists());
        assert!(!running.exists());
    }
}
