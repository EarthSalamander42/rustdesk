#!/usr/bin/env bash
# FS Support — contrôle de l'installeur .pkg sur le runner macOS de la CI (jamais sur un Mac client).
#
# Usage : bash res/fs/macos/pkg/verifier-pkg.sh <fichier.pkg> <version> <rapport.txt>
#
# 1. pkgutil --check-signature (non signé attendu : simple relevé) ;
# 2. pkgutil --expand-full : l'app, preinstall, postinstall et les écrans en français sont bien dedans ;
# 3. installation réelle (sudo installer -pkg … -target /) d'une copie mise en QUARANTAINE comme après un
#    téléchargement par navigateur, puis : /Applications/FS Support.app présente, sans quarantaine, signature
#    valide, binaire qui répond --version, interface ouverte par postinstall (relevé seulement).
# Sortie non nulle si un contrôle essentiel échoue.
set -uo pipefail

PKG="${1:?fichier .pkg manquant}"
VERSION="${2:?version manquante}"
RAPPORT="${3:?fichier de rapport manquant}"
APP_NAME="FS Support"
DEST="/Applications/${APP_NAME}.app"
erreurs=0

exec > >(tee "$RAPPORT") 2>&1
ok() { echo "OK      $*"; }
ko() { echo "ÉCHEC   $*"; echo "::error title=Installeur .pkg::$*"; erreurs=$((erreurs + 1)); }
info() { echo "INFO    $*"; }

echo "== Installeur : $(basename "$PKG") ($(du -h "$PKG" | cut -f1)), version attendue $VERSION"

echo "== 1. Signature du .pkg"
/usr/sbin/pkgutil --check-signature "$PKG" || true
info "un .pkg sans certificat « Developer ID Installer » est attendu non signé (macOS demande « Ouvrir quand même »)"

echo "== 2. Contenu"
X="$(mktemp -d "${RUNNER_TEMP:-/tmp}/fs-pkg-x.XXXXXX")/x"
if /usr/sbin/pkgutil --expand-full "$PKG" "$X"; then
	ok "pkgutil --expand-full"
	find "$X" -maxdepth 2 | sed "s#^$X#  #"
	C="$X/fs-support-composant.pkg"
	[ -f "$C/Payload/Applications/${APP_NAME}.app/Contents/Info.plist" ] && ok "charge utile : Applications/${APP_NAME}.app" || ko "app absente de la charge utile"
	[ -f "$C/Scripts/postinstall" ] && ok "script postinstall présent" || ko "postinstall absent"
	[ -f "$C/Scripts/preinstall" ] && ok "script preinstall présent" || ko "preinstall absent"
	grep -q 'xattr -dr com.apple.quarantine "\$DEST"' "$C/Scripts/postinstall" && ok "postinstall : quarantaine retirée de l'app seulement" || ko "postinstall sans retrait de quarantaine"
	if cat "$C/Scripts/preinstall" "$C/Scripts/postinstall" | grep -v '^[[:space:]]*#' | grep -Eq 'spctl|csrutil'; then
		ko "un script touche à Gatekeeper ou à SIP"
	else
		ok "aucun réglage global de Gatekeeper ni de SIP"
	fi
	grep -q 'Installer FS Support' "$X/Resources/welcome.html" && ok "écran d'accueil en français" || ko "écran d'accueil absent"
	grep -q 'FS Support est installé' "$X/Resources/conclusion.html" && ok "écran de fin en français" || ko "écran de fin absent"
	grep -o '<bundle [^>]*>' "$C/PackageInfo" 2>/dev/null | sed 's/^/  /' || true
	/usr/bin/codesign --verify --deep --strict "$C/Payload/Applications/${APP_NAME}.app" && ok "signature de l'app dans le .pkg" || ko "signature de l'app dans le .pkg"
	/usr/bin/codesign -dvv "$C/Payload/Applications/${APP_NAME}.app" 2>&1 | grep -E '^(Identifier|Authority|Signature|TeamIdentifier)=' | sed 's/^/  /'
else
	ko "pkgutil --expand-full"
fi

echo "== 3. Installation sur le runner (copie en quarantaine, comme téléchargée par Safari)"
Q="$(dirname "$X")/telecharge.pkg"
cp "$PKG" "$Q"
/usr/bin/xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;" "$Q"
/usr/bin/xattr -p com.apple.quarantine "$Q" >/dev/null 2>&1 && info "copie du .pkg en quarantaine"
/usr/sbin/spctl --assess --type install -vv "$Q" 2>&1 | sed 's/^/  spctl : /' || true
info "utilisateur à l'écran : $(stat -f %Su /dev/console 2>/dev/null || echo ?)"
if sudo /usr/sbin/installer -pkg "$Q" -target / -verboseR; then
	ok "sudo installer -pkg … -target /"
else
	ko "installer a échoué"
fi
echo "-- journal d'installation (FS Support)"
grep -a 'FS Support p' /var/log/install.log | tail -n 20 | sed 's/^/  /' || true

if [ -d "$DEST" ]; then
	ok "$DEST présente"
	if /usr/bin/xattr -lr "$DEST" 2>/dev/null | grep -q com.apple.quarantine; then ko "quarantaine encore présente sur l'app"; else ok "aucune quarantaine sur l'app"; fi
	/usr/bin/codesign --verify --deep --strict "$DEST" && ok "codesign --verify (app installée)" || ko "signature de l'app installée"
	info "propriétaire : $(stat -f '%Su:%Sg' "$DEST")"
	EXE="$(/usr/bin/defaults read "$DEST/Contents/Info" CFBundleExecutable 2>/dev/null || echo "$APP_NAME")"
	V="$(perl -e 'alarm 60; exec @ARGV' "$DEST/Contents/MacOS/$EXE" --version 2>/dev/null | tail -n 1 || true)"
	if [ -n "$V" ]; then ok "lançable : --version répond « $V »"; else ko "le binaire ne répond pas à --version"; fi
	[ "$V" = "$VERSION" ] || info "version de l'app « $V » (attendue $VERSION : différente sur une compilation de contrôle, normal)"
	sleep 8
	if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
		ok "interface FS Support ouverte par postinstall"
		pkill -x "$APP_NAME" 2>/dev/null || true
	else
		info "interface non vue après 8 s (session graphique du runner) : relevé seulement"
	fi
	/usr/sbin/pkgutil --pkg-info fr.fs-solutions.support | sed 's/^/  /' || true
else
	ko "$DEST absente après installation"
fi

echo "== Bilan : $erreurs échec(s)"
[ "$erreurs" -eq 0 ]
