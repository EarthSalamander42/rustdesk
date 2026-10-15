#!/usr/bin/env python3
# FS Support : contrôle des icônes de l'application (logo « casque », 16/10/2026) et planches de contrôle.
#
# Vérifie, sans compiler, les fichiers que les compilations embarquent : tailles des ICO Windows, entrées
# de l'ICNS macOS, mipmaps Android (dont la couche monochrome et l'icône de notification), couleurs,
# copies identiques et présence dans git (la racine du dépôt ignore *png). Les écarts sortent en
# annotations GitHub et le script se termine en erreur.
#
# Usage : python3 res/fs/icones/verifier-icones.py [--planches <dossier>]
# Avec --planches, écrit des PNG de contrôle (Windows, Android, macOS) dans <dossier>.
import argparse
import hashlib
import os
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageColor, ImageDraw, ImageFont

RACINE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ANDROID = "flutter/android/app/src/main/res"
DENSITES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
TAILLES_ICO_APP = [16, 20, 24, 32, 40, 48, 64, 128, 256]
TAILLES_ICO_TRAY = [16, 20, 24, 32, 40, 48, 64]
CREME = "#f4efe2"

erreurs = []
notes = []


def chemin(p):
    return os.path.join(RACINE, p)


def erreur(fichier, message):
    erreurs.append((fichier, message))


def octets(p):
    with open(chemin(p), "rb") as f:
        return f.read()


def empreinte(p):
    return hashlib.sha256(octets(p)).hexdigest()


def entrees_ico(p):
    """[(côté, image RGBA, est_png)] dans l'ordre du fichier."""
    donnees = octets(p)
    _, type_, n = struct.unpack_from("<HHH", donnees, 0)
    if type_ != 1:
        raise ValueError("pas un ICO")
    res = []
    for i in range(n):
        l, h, _, _, _, _, taille, debut = struct.unpack_from("<BBBBHHII", donnees, 6 + 16 * i)
        brut = donnees[debut:debut + taille]
        est_png = brut.startswith(b"\x89PNG")
        cote = l or 256
        res.append((cote, Image.open(chemin(p)).ico.getimage((cote, h or 256)).convert("RGBA"), est_png))
    return res


def types_icns(p):
    donnees = octets(p)
    if donnees[:4] != b"icns":
        raise ValueError("pas un ICNS")
    o, types = 8, []
    while o < len(donnees):
        t, l = struct.unpack_from(">4sI", donnees, o)
        types.append(t.decode("ascii", "replace"))
        o += l
    return types


def image_icns(p, taille):
    """Entrée (largeur, hauteur, échelle) d'un ICNS ; fichier rouvert à chaque fois (Pillow garde la
    dernière image chargée quand deux entrées ont le même nombre de pixels, 32@1x et 16@2x par ex.)."""
    im = Image.open(chemin(p))
    im.size = taille
    im.load()
    return im.convert("RGBA")


def png(p):
    return Image.open(chemin(p)).convert("RGBA")


def suivi_par_git(p):
    r = subprocess.run(["git", "ls-files", "--error-unmatch", p], cwd=RACINE,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return r.returncode == 0


def couleurs_opaques(im, seuil=8):
    return {px[:3] for px in im.getdata() if px[3] > seuil}


def verifier():
    # Windows : icône de l'application (exe, raccourcis, fenêtre, installeur, paquet portable).
    copies_ico = ["res/icon.ico", "flutter/assets/icon.ico",
                  "flutter/windows/runner/resources/app_icon.ico", "res/msi/Package/Resources/icon.ico"]
    ref = empreinte("res/icon.ico")
    for p in copies_ico:
        if empreinte(p) != ref:
            erreur(p, "différent de res/icon.ico")
    tailles = [c for c, _, _ in entrees_ico("res/icon.ico")]
    if sorted(tailles) != TAILLES_ICO_APP:
        erreur("res/icon.ico", f"tailles {tailles}, attendu {TAILLES_ICO_APP}")
    tailles = [c for c, _, _ in entrees_ico("res/tray-icon.ico")]
    if sorted(tailles) != TAILLES_ICO_TRAY:
        erreur("res/tray-icon.ico", f"tailles {tailles}, attendu {TAILLES_ICO_TRAY}")
    for p in ("res/icon.ico", "res/tray-icon.ico"):
        if not all(est_png for _, _, est_png in entrees_ico(p)):
            erreur(p, "entrée non PNG (src/fs_tray.rs ne lit que les PNG)")
    notes.append(f"res/icon.ico : {sorted(c for c, _, _ in entrees_ico('res/icon.ico'))}")
    notes.append(f"res/tray-icon.ico : {sorted(c for c, _, _ in entrees_ico('res/tray-icon.ico'))}")

    # macOS : icône de l'app (ICNS) et barre des menus (gabarit : seul l'alpha compte).
    types = types_icns("flutter/macos/Runner/AppIcon.icns")
    attendus = {"icp4": 16, "icp5": 32, "icp6": 64, "ic07": 128, "ic08": 256, "ic09": 512, "ic10": 1024,
                "ic11": 32, "ic12": 64, "ic13": 256, "ic14": 512}
    manquants = [t for t in attendus if t not in types]
    if manquants:
        erreur("flutter/macos/Runner/AppIcon.icns", f"entrées manquantes {manquants} (présentes {types})")
    notes.append(f"AppIcon.icns : {' '.join(types)}")
    im = Image.open(chemin("flutter/macos/Runner/AppIcon.icns"))
    tailles_icns = sorted(im.info.get("sizes", []))
    if (512, 512, 2) not in tailles_icns:
        erreur("flutter/macos/Runner/AppIcon.icns", "pas de 1024 px (512@2x)")
    if png("res/mac-icon.png").size != (512, 512):
        erreur("res/mac-icon.png", f"taille {png('res/mac-icon.png').size}, attendu 512×512")
    for p, teinte in (("res/mac-tray-light-x2.png", (0, 0, 0)), ("res/mac-tray-dark-x2.png", (255, 255, 255))):
        im = png(p)
        if im.size != (60, 60):
            erreur(p, f"taille {im.size}, attendu 60×60")
        autres = {c for c in couleurs_opaques(im, 128) if max(abs(a - b) for a, b in zip(c, teinte)) > 24}
        if autres:
            erreur(p, f"silhouette non unie ({len(autres)} couleurs hors {teinte})")

    # Android : lanceur, icône adaptative, couche monochrome (Android 13+), notification.
    for nom, base in (("ic_launcher", 48), ("ic_launcher_round", 48), ("ic_launcher_foreground", 108),
                      ("ic_launcher_monochrome", 108), ("ic_stat_logo", 24)):
        for d, k in DENSITES.items():
            p = f"{ANDROID}/mipmap-{d}/{nom}.png"
            if not os.path.exists(chemin(p)):
                erreur(p, "absent")
                continue
            if not suivi_par_git(p):
                erreur(p, "non versionné (git add -f : la racine ignore *png)")
            im = png(p)
            attendu = int(base * k)
            if im.size != (attendu, attendu):
                erreur(p, f"taille {im.size}, attendu {attendu}×{attendu}")
            if nom == "ic_stat_logo":
                autres = {c for c in couleurs_opaques(im, 128) if min(c) < 230}
                if autres:
                    erreur(p, "l'icône de notification doit être une silhouette blanche")
    for nom in ("ic_launcher.xml", "ic_launcher_round.xml"):
        p = f"{ANDROID}/mipmap-anydpi-v26/{nom}"
        ns = "{http://schemas.android.com/apk/res/android}drawable"
        couches = {e.tag: e.get(ns) for e in ET.parse(chemin(p)).getroot()}
        if couches.get("monochrome") != "@mipmap/ic_launcher_monochrome":
            erreur(p, f"monochrome = {couches.get('monochrome')}")
        if couches.get("foreground") != "@mipmap/ic_launcher_foreground":
            erreur(p, f"foreground = {couches.get('foreground')}")
    fond = ET.parse(chemin(f"{ANDROID}/values/ic_launcher_background.xml")).getroot().find("color").text.strip()
    if fond.lower() != CREME:
        erreur(f"{ANDROID}/values/ic_launcher_background.xml", f"fond {fond}, attendu {CREME}")

    # Commun : logo dans l'application, Linux, fiche F-Droid.
    ref = empreinte("res/icon.png")
    for p in ("flutter/assets/icon.png", "flutter/assets/logo.png", "fastlane/metadata/android/en-US/images/icon.png"):
        if empreinte(p) != ref:
            erreur(p, "différent de res/icon.png")
    if empreinte("res/scalable.svg") != empreinte("flutter/assets/icon.svg"):
        erreur("res/scalable.svg", "différent de flutter/assets/icon.svg")
    for p, c in (("res/32x32.png", 32), ("res/64x64.png", 64), ("res/128x128.png", 128),
                 ("res/128x128@2x.png", 256), ("res/icon.png", 512)):
        if png(p).size != (c, c):
            erreur(p, f"taille {png(p).size}, attendu {c}×{c}")
    for p in ("res/icon.png", "res/mac-icon.png", "res/mac-tray-light-x2.png", "res/mac-tray-dark-x2.png",
              "res/32x32.png", "res/64x64.png", "res/128x128.png", "res/128x128@2x.png",
              "flutter/assets/icon.png", "flutter/assets/logo.png", "fastlane/metadata/android/en-US/images/icon.png"):
        if not suivi_par_git(p):
            erreur(p, "non versionné (git add -f : la racine ignore *png)")


# ---------------------------------------------------------------------------------------------------
# Planches

def police(taille):
    try:
        return ImageFont.load_default(size=taille)
    except TypeError:
        return ImageFont.load_default()


class Planche:
    def __init__(self, titre, largeur=1400):
        self.largeur, self.lignes = largeur, []
        self.titre = titre

    def ligne(self, legende, cases, fond="#ffffff", hauteur=None):
        """cases : liste de (image, étiquette)."""
        h = hauteur or max(im.height for im, _ in cases) + 40
        self.lignes.append((legende, cases, fond, h))

    def enregistrer(self, p):
        h_total = 70 + sum(h + 34 for *_, h in self.lignes) + 20
        toile = Image.new("RGBA", (self.largeur, h_total), "#fbfaf6")
        d = ImageDraw.Draw(toile)
        d.text((24, 20), self.titre, fill="#1d2023", font=police(26))
        y = 70
        for legende, cases, fond, h in self.lignes:
            d.text((24, y), legende, fill="#1d2023", font=police(17))
            y += 26
            d.rounded_rectangle((16, y, self.largeur - 16, y + h), 10, fill=fond)
            x = 32
            for im, etiquette in cases:
                toile.alpha_composite(im, (x, y + (h - 22 - im.height) // 2))
                clair = sum(ImageColor.getrgb(fond)) > 384
                d.text((x, y + h - 20), etiquette, fill="#3b3f43" if clair else "#d8d8d8", font=police(13))
                x += max(im.width, 44) + 22
            y += h + 8
        toile.convert("RGB").save(p, optimize=True)


def agrandi(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def teinte(masque, couleur):
    im = Image.new("RGBA", masque.size, couleur)
    im.putalpha(masque.getchannel("A"))
    return im


def masque_forme(cote, forme):
    m = Image.new("L", (cote * 4, cote * 4), 0)
    d = ImageDraw.Draw(m)
    if forme == "cercle":
        d.ellipse((0, 0, cote * 4 - 1, cote * 4 - 1), fill=255)
    elif forme == "squircle":
        d.rounded_rectangle((0, 0, cote * 4 - 1, cote * 4 - 1), int(cote * 4 * 0.32), fill=255)
    else:
        d.rounded_rectangle((0, 0, cote * 4 - 1, cote * 4 - 1), int(cote * 4 * 0.12), fill=255)
    return m.resize((cote, cote), Image.LANCZOS)


def adaptative(fond, avant_plan, cote, forme):
    """Icône adaptative telle que le lanceur la découpe : 108 dp de calque, 72 dp visibles."""
    calque = Image.new("RGBA", avant_plan.size, fond)
    calque.alpha_composite(avant_plan)
    marge = avant_plan.width // 6
    visible = calque.crop((marge, marge, avant_plan.width - marge, avant_plan.height - marge))
    visible = visible.resize((cote, cote), Image.LANCZOS)
    sortie = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    sortie.paste(visible, (0, 0), masque_forme(cote, forme))
    return sortie


def planche_windows(sortie):
    pl = Planche("FS Support · Windows : icône de l'application et zone de notification")
    app = entrees_ico("res/icon.ico")
    tray = entrees_ico("res/tray-icon.ico")
    for fond, nom in (("#f3f3f3", "barre des tâches claire"), ("#202020", "barre des tâches sombre")):
        pl.ligne(f"res/icon.ico ({nom}) : taille réelle", [(im, f"{c}") for c, im, _ in app], fond)
        pl.ligne(f"res/tray-icon.ico ({nom}) : taille réelle (16-32 = casque autour du monogramme)",
                 [(im, f"{c}") for c, im, _ in tray], fond)
    pl.ligne("res/icon.ico, petites tailles agrandies ×6 (sans lissage)",
             [(agrandi(im, 6), f"{c} px") for c, im, _ in app if c <= 32], "#f3f3f3")
    pl.ligne("res/tray-icon.ico, petites tailles agrandies ×6, sur fond sombre",
             [(agrandi(im, 6), f"{c} px") for c, im, _ in tray if c <= 32], "#202020")
    pl.enregistrer(os.path.join(sortie, "logo-windows.png"))


def planche_android(sortie):
    pl = Planche("FS Support · Android : lanceur, icône adaptative, Android 13+ monochrome, notification")
    fond = ET.parse(chemin(f"{ANDROID}/values/ic_launcher_background.xml")).getroot().find("color").text.strip()
    av = png(f"{ANDROID}/mipmap-xxxhdpi/ic_launcher_foreground.png")
    mono = png(f"{ANDROID}/mipmap-xxxhdpi/ic_launcher_monochrome.png")
    cases = [(adaptative(fond, av, 144, f), f"{f}") for f in ("cercle", "squircle", "carré arrondi")]
    pl.ligne(f"Icône adaptative (fond {fond} + avant-plan xxxhdpi), trois masques de lanceur", cases, "#dfe3e8")
    pl.ligne("Icône adaptative sur fond d'écran sombre",
             [(adaptative(fond, av, 144, f), f) for f in ("cercle", "squircle")], "#1b1d21")
    themes = [(adaptative("#d3e3fd", teinte(mono, "#041e49"), 144, "cercle"), "thème clair"),
              (adaptative("#004a77", teinte(mono, "#c2e7ff"), 144, "cercle"), "thème sombre")]
    pl.ligne("Icône à thème (Android 13+) : couche monochrome teintée par le système", themes, "#eef1f5")
    pl.ligne("Anciennes icônes (avant Android 8) : ic_launcher et ic_launcher_round, mdpi → xxxhdpi",
             [(png(f"{ANDROID}/mipmap-{d}/ic_launcher.png"), d) for d in DENSITES]
             + [(png(f"{ANDROID}/mipmap-{d}/ic_launcher_round.png"), d) for d in ("xhdpi", "xxxhdpi")], "#dfe3e8")
    notif = [(png(f"{ANDROID}/mipmap-{d}/ic_stat_logo.png"), d) for d in DENSITES]
    pl.ligne("Notification (ic_stat_logo) : barre d'état sombre", notif, "#101114")
    pl.ligne("Notification : teintée par le système sur barre claire, et agrandie ×4 (mdpi, 24 px)",
             [(teinte(im, "#49454f"), d) for im, d in notif] +
             [(agrandi(teinte(notif[0][0], "#49454f"), 4), "mdpi ×4")], "#f7f2fa")
    pl.ligne("Fiche F-Droid (fastlane, 512 px, réduite à 160)",
             [(png("fastlane/metadata/android/en-US/images/icon.png").resize((160, 160), Image.LANCZOS),
               "icon.png")], "#ffffff")
    pl.enregistrer(os.path.join(sortie, "logo-android.png"))


def planche_macos(sortie):
    pl = Planche("FS Support · macOS : icône de l'application (AppIcon.icns) et barre des menus")
    icns = "flutter/macos/Runner/AppIcon.icns"
    cases = []
    for (w, h, k) in sorted(Image.open(chemin(icns)).info.get("sizes", []), key=lambda s: (s[0] * s[2], s[2])):
        img = image_icns(icns, (w, h, k))
        cote = w * k
        if img.size != (cote, cote):
            erreur(icns, f"entrée {w}@{k}x : image {img.size}, attendu {cote}×{cote}")
        affiche = img if cote <= 256 else img.resize((256, 256), Image.LANCZOS)
        cases.append((affiche, f"{w}@{k}x ({cote})"))
    pl.ligne("AppIcon.icns : toutes les entrées (≥ 512 réduites à 256 pour la planche)", cases, "#ffffff")
    pl.ligne("AppIcon.icns sur le Dock sombre", [(c, e) for c, e in cases if c.width <= 128], "#2b2b2e")
    gabarit = png("res/mac-tray-dark-x2.png")
    barre = []
    for cote in (18, 22, 36):
        g = gabarit.resize((cote, cote), Image.LANCZOS)
        barre.append((teinte(g, "#000000"), f"{cote} px"))
    pl.ligne("Barre des menus claire (gabarit rendu en noir par macOS)", barre, "#ececec")
    pl.ligne("Barre des menus sombre (gabarit rendu en blanc)",
             [(teinte(im_, "#ffffff"), e) for im_, e in barre], "#1e1e1e")
    pl.ligne("Fichiers mac-tray-light-x2 / mac-tray-dark-x2 (60 × 60)",
             [(png("res/mac-tray-light-x2.png"), "light"), (png("res/mac-tray-dark-x2.png"), "dark")], "#8a8f94")
    pl.enregistrer(os.path.join(sortie, "logo-macos.png"))


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--planches")
    args = a.parse_args()
    try:
        verifier()
    except Exception as e:  # fichier illisible : erreur nette plutôt qu'une trace
        erreur("-", f"{type(e).__name__}: {e}")
    for n in notes:
        print(n)
    if args.planches:
        os.makedirs(args.planches, exist_ok=True)
        for f in (planche_windows, planche_android, planche_macos):
            try:
                f(args.planches)
            except Exception as e:
                erreur("-", f"planche {f.__name__} : {type(e).__name__}: {e}")
    for fichier, message in erreurs:
        print(f"::error file={fichier}::{message}" if fichier != "-" else f"::error::{message}")
    if erreurs:
        sys.exit(1)
    print(f"::notice title=Icônes FS Support::contrôles OK ({len(notes)} relevés)")


if __name__ == "__main__":
    main()
