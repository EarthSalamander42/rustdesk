// FS Support : icône de la zone de notification (Windows) et de la barre des menus (macOS).
//
// `tray::load_icon_from_asset` lit `assets/icon.png`, l'icône de l'application : une tuile pleine,
// que macOS rend en gabarit (seul l'alpha compte, donc un carré uni) et que Windows réduit à 16 px.
// FS Support a ses propres dessins pour ces deux endroits : le casque autour du monogramme
// (`res/tray-icon.ico` de 16 à 32 px, silhouette `res/mac-tray-dark-x2.png`).

#[cfg(target_os = "macos")]
pub fn icone() -> Option<image::DynamicImage> {
    image::load_from_memory(include_bytes!("../res/mac-tray-dark-x2.png")).ok()
}

// Windows affiche l'icône à la taille « petite icône » du système (16 px à 100 %, 20 à 125 %, 24 à
// 150 %, 32 à 200 %) : on prend l'entrée exacte de l'ICO plutôt que de laisser réduire la plus grande.
#[cfg(windows)]
pub fn icone() -> Option<image::DynamicImage> {
    use winapi::um::winuser::{GetSystemMetrics, SM_CXSMICON};
    let cote = unsafe { GetSystemMetrics(SM_CXSMICON) };
    let cote = if cote > 0 { cote as u32 } else { 16 };
    let png = entree_ico(include_bytes!("../res/tray-icon.ico"), cote)?;
    image::load_from_memory(png).ok()
}

#[cfg(not(any(windows, target_os = "macos")))]
pub fn icone() -> Option<image::DynamicImage> {
    None
}

/// Entrée PNG d'un fichier ICO la plus proche de `cote` : la plus petite qui l'atteint, sinon la plus
/// grande. `None` si le fichier est invalide ou si l'entrée retenue n'est pas un PNG.
#[cfg_attr(not(windows), allow(dead_code))]
fn entree_ico(ico: &[u8], cote: u32) -> Option<&[u8]> {
    let u16_le = |o: usize| Some(u16::from_le_bytes(ico.get(o..o + 2)?.try_into().ok()?));
    let u32_le = |o: usize| Some(u32::from_le_bytes(ico.get(o..o + 4)?.try_into().ok()?));
    if u16_le(0)? != 0 || u16_le(2)? != 1 {
        return None;
    }
    let mut entrees = Vec::new();
    for i in 0..u16_le(4)? as usize {
        let e = 6 + 16 * i;
        let largeur = match *ico.get(e)? {
            0 => 256,
            l => l as u32,
        };
        let taille = u32_le(e + 8)? as usize;
        let debut = u32_le(e + 12)? as usize;
        entrees.push((largeur, ico.get(debut..debut.checked_add(taille)?)?));
    }
    let (_, donnees) = entrees
        .iter()
        .filter(|(l, _)| *l >= cote)
        .min_by_key(|(l, _)| *l)
        .or_else(|| entrees.iter().max_by_key(|(l, _)| *l))?;
    donnees.starts_with(b"\x89PNG").then_some(*donnees)
}

#[cfg(test)]
mod tests {
    use super::entree_ico;

    const TRAY: &[u8] = include_bytes!("../res/tray-icon.ico");

    fn largeur(png: &[u8]) -> u32 {
        u32::from_be_bytes(png[16..20].try_into().unwrap())
    }

    #[test]
    fn taille_exacte_de_la_zone_de_notification() {
        for cote in [16, 20, 24, 32, 40, 48, 64] {
            assert_eq!(largeur(entree_ico(TRAY, cote).unwrap()), cote);
        }
    }

    #[test]
    fn taille_intermediaire_ou_trop_grande() {
        assert_eq!(largeur(entree_ico(TRAY, 18).unwrap()), 20);
        assert_eq!(largeur(entree_ico(TRAY, 96).unwrap()), 64);
    }

    #[test]
    fn fichier_invalide() {
        assert!(entree_ico(b"pas un ico", 16).is_none());
        assert!(entree_ico(&TRAY[..40], 16).is_none());
    }
}
