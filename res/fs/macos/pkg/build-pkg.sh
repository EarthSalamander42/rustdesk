#!/usr/bin/env bash
# FS Support — installeur .pkg macOS (gratuit : pkgbuild + productbuild, sans certificat Apple).
# CI GitHub, runner macOS uniquement (jamais sur FS-DS-1).
#
# Usage : bash res/fs/macos/pkg/build-pkg.sh "<chemin>/FS Support.app" <version> <x86_64|aarch64> <sortie.pkg>
#
# Charge utile : l'app EXACTE du .dmg (même signature : certificat auto-signé constant si les secrets
# FS_MACOS_SIGN_* existent, sinon ad hoc), installée dans /Applications. Scripts : scripts/preinstall
# (ferme l'interface) et scripts/postinstall (quarantaine de l'app retirée, signature vérifiée, relance).
# Écrans d'accueil et de fin en français : resources/welcome.html et conclusion.html.
# Le .pkg n'est PAS signé (il faudrait un certificat « Developer ID Installer » payant) : macOS 15 demande
# une fois « Ouvrir quand même » dans Réglages Système › Confidentialité et sécurité.
set -euo pipefail

APP="${1:?chemin de l’app manquant}"
VERSION="${2:?version manquante}"
ARCH="${3:?architecture manquante (x86_64 ou aarch64)}"
OUT="${4:?fichier .pkg de sortie manquant}"
APP_NAME="FS Support"
PKG_ID="fr.fs-solutions.support"
K="$(cd "$(dirname "$0")" && pwd)"

case "$ARCH" in
aarch64 | arm64) ARCH=aarch64; ARCH_LABEL="Mac à puce Apple" ;;
x86_64) ARCH_LABEL="Mac à processeur Intel" ;;
*) echo "architecture inconnue : $ARCH" >&2; exit 1 ;;
esac
[ -d "$APP" ] || { echo "app introuvable : $APP" >&2; exit 1; }
printf '%s' "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+)*$' || { echo "version invalide : $VERSION" >&2; exit 1; }

W="$(mktemp -d "${RUNNER_TEMP:-/tmp}/fs-pkg.XXXXXX")"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/root/Applications" "$W/scripts" "$W/resources" "$W/paquets"

# Même app que le .dmg, attributs étendus et signature compris.
/usr/bin/ditto "$APP" "$W/root/Applications/${APP_NAME}.app"
/usr/bin/codesign --verify --deep --strict "$W/root/Applications/${APP_NAME}.app"

install -m 0755 "$K/scripts/preinstall" "$W/scripts/preinstall"
install -m 0755 "$K/scripts/postinstall" "$W/scripts/postinstall"
# Fichiers du dépôt éventuellement en CRLF (extraction Windows) : bash refuserait « \r ».
sed -i '' -e $'s/\r$//' "$W/scripts/preinstall" "$W/scripts/postinstall"
bash -n "$W/scripts/preinstall"
bash -n "$W/scripts/postinstall"

for f in welcome.html conclusion.html; do
	sed -e "s/__VERSION__/${VERSION}/g" -e "s/__ARCH_LABEL__/${ARCH_LABEL}/g" "$K/resources/$f" > "$W/resources/$f"
done

# Composant : jamais « relogeable » (sinon Installer remplacerait une copie trouvée ailleurs sur le disque
# au lieu d'écrire dans /Applications) ; pas de refus d'une version égale (builds de test au même numéro).
/usr/bin/pkgbuild --analyze --root "$W/root" "$W/composant.plist"
# Entrées de premier niveau seulement (les sous-bundles sont dans ChildBundles).
i=0
while /usr/libexec/PlistBuddy -c "Print :$i:RootRelativeBundlePath" "$W/composant.plist" >/dev/null 2>&1; do
	/usr/libexec/PlistBuddy -c "Set :$i:BundleIsRelocatable false" "$W/composant.plist"
	/usr/libexec/PlistBuddy -c "Set :$i:BundleIsVersionChecked false" "$W/composant.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Set :$i:BundleOverwriteAction upgrade" "$W/composant.plist" 2>/dev/null || true
	i=$((i + 1))
done
[ "$i" -ge 1 ] || { echo "composant.plist sans bundle" >&2; exit 1; }

/usr/bin/pkgbuild \
	--root "$W/root" \
	--component-plist "$W/composant.plist" \
	--scripts "$W/scripts" \
	--identifier "$PKG_ID" \
	--version "$VERSION" \
	--install-location / \
	"$W/paquets/fs-support-composant.pkg"

# Installeur « Apple silicon » refusé proprement sur un Mac Intel (l'app ne s'y lancerait pas).
# L'installeur Intel reste accepté partout (Rosetta sur puce Apple).
cat > "$W/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
	<title>${APP_NAME}</title>
	<organization>fr.fs-solutions</organization>
	<welcome file="welcome.html" mime-type="text/html"/>
	<conclusion file="conclusion.html" mime-type="text/html"/>
	<options customize="never" require-scripts="false" rootVolumeOnly="true" hostArchitectures="x86_64,arm64"/>
	<domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
	<installation-check script="verifierMac()"/>
	<script><![CDATA[
function verifierMac() {
	if ('${ARCH}' == 'aarch64' && system.sysctl('hw.optional.arm64') != 1) {
		my.result.title = 'Installeur pour Mac à puce Apple';
		my.result.message = 'Ce Mac a un processeur Intel. Téléchargez l\'installeur « Intel » de FS Support.';
		my.result.type = 'Fatal';
		return false;
	}
	return true;
}
	]]></script>
	<choices-outline>
		<line choice="fs-support"/>
	</choices-outline>
	<choice id="fs-support" visible="false" title="${APP_NAME}">
		<pkg-ref id="${PKG_ID}"/>
	</choice>
	<pkg-ref id="${PKG_ID}" version="${VERSION}" onConclusion="none">fs-support-composant.pkg</pkg-ref>
</installer-gui-script>
EOF

/usr/bin/productbuild \
	--distribution "$W/distribution.xml" \
	--resources "$W/resources" \
	--package-path "$W/paquets" \
	--identifier "$PKG_ID.installeur" \
	--version "$VERSION" \
	"$OUT"

echo "Installeur prêt : $OUT ($(du -h "$OUT" | cut -f1))"
