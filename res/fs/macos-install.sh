#!/bin/bash
# FS Support — installation (ou mise à jour) sur macOS, en une commande à coller dans le Terminal :
#
#   curl -fsSL https://github.com/EarthSalamander42/rustdesk/releases/download/fs-nightly/fs-support-macos-install.sh | bash
#
# Pourquoi : l'application n'est ni signée « Developer ID » ni notariée. Ouverte depuis un .dmg téléchargé
# par un navigateur, elle porte l'attribut de quarantaine et macOS la dit « endommagée ». Un fichier
# téléchargé par curl ne reçoit pas cet attribut : l'installation se fait sans détour.
#
# Étapes : processeur → adresse du .dmg (API FS, à défaut la release GitHub « fs-nightly ») → téléchargement →
# montage → fermeture de FS Support → remplacement de /Applications/FS Support.app → démontage →
# quarantaine retirée → signature vérifiée (re-signature ad hoc au besoin) → ouverture.
#
# Pour essayer un autre .dmg (build de test « fs-test ») :
#   curl -fsSL <adresse du script> | FS_SUPPORT_DMG_URL=<adresse du .dmg> bash
#
# Écrit pour le bash 3.2 livré avec macOS. Publié à chaque nuit par .github/workflows/fs-support-nightly.yml.
# Tout est dans main(), appelée à la dernière ligne : bash lit le script en entier avant d'agir (curl | bash).

set -euo pipefail

APP_NAME="FS Support"
DEST="/Applications/${APP_NAME}.app"
API_URL="https://api.fs-solutions.fr/public/support/rustdesk-version"
GITHUB_RELEASE_API="https://api.github.com/repos/EarthSalamander42/rustdesk/releases/tags/fs-nightly"

WORK_DIR=""
MOUNT_POINT=""
MOUNTED=0
USE_SUDO=0
ARCH=""
VERSION=""
DMG_URL=""

info() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
fail() {
	printf '\n\033[1;31mErreur :\033[0m %s\n' "$*" >&2
	exit 1
}

detach_image() {
	[ "$MOUNTED" = 1 ] || return 0
	if hdiutil detach -quiet "$MOUNT_POINT" >/dev/null 2>&1 || hdiutil detach -force -quiet "$MOUNT_POINT" >/dev/null 2>&1; then
		MOUNTED=0
	fi
}

cleanup() {
	detach_image
	if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
		# Image encore montée : on ne touche pas au dossier (rm -rf traverserait le point de montage).
		if [ "$MOUNTED" = 1 ]; then
			note "Image disque encore montée sur $MOUNT_POINT : éjectez-la depuis le Finder."
		else
			rm -rf "$WORK_DIR"
		fi
	fi
}

# Valeur texte d'une clé de premier niveau d'un objet JSON ($1 = JSON, $2 = clé). Pas de jq sur macOS :
# JavaScript d'osascript, sinon plutil (macOS 12 et plus), sinon sed. python3 est évité : sans les outils
# de développement, /usr/bin/python3 ouvre une fenêtre proposant de les installer.
json_get() {
	local json="$1" key="$2" value=""
	value="$(/usr/bin/osascript -l JavaScript \
		-e 'function run(a){try{var v=JSON.parse(a[0])[a[1]];return (v===undefined||v===null)?"":String(v);}catch(e){return "";}}' \
		"$json" "$key" 2>/dev/null || true)"
	if [ -z "$value" ]; then
		value="$(printf '%s' "$json" | /usr/bin/plutil -extract "$key" raw -o - - 2>/dev/null || true)"
	fi
	if [ -z "$value" ]; then
		value="$(printf '%s' "$json" | tr -d '\n' |
			sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 's#\\/#/#g' || true)"
	fi
	printf '%s' "$value"
}

detect_arch() {
	# Sur Apple Silicon, un Terminal ouvert sous Rosetta répond x86_64 à uname -m : on interroge le noyau.
	if [ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" = "1" ]; then
		ARCH="aarch64"
		return 0
	fi
	case "$(uname -m)" in
	arm64 | aarch64) ARCH="aarch64" ;;
	x86_64) ARCH="x86_64" ;;
	*) fail "Processeur non pris en charge : $(uname -m)." ;;
	esac
}

# Renseigne DMG_URL (et VERSION si possible) : API FS d'abord, release GitHub « fs-nightly » ensuite.
find_dmg_url() {
	local json url
	if [ -n "${FS_SUPPORT_DMG_URL:-}" ]; then
		DMG_URL="$FS_SUPPORT_DMG_URL"
		note "Image disque imposée : $DMG_URL"
		return 0
	fi
	json="$(curl -fsSL --connect-timeout 15 --max-time 30 "${API_URL}?platform=macos&arch=${ARCH}" 2>/dev/null || true)"
	if [ -n "$json" ]; then
		url="$(json_get "$json" url)"
		case "$url" in
		https://*)
			DMG_URL="$url"
			VERSION="$(json_get "$json" version)"
			return 0
			;;
		esac
	fi
	note "Le serveur FS ne répond pas : téléchargement depuis GitHub."
	json="$(curl -fsSL --connect-timeout 15 --max-time 30 -H 'Accept: application/vnd.github+json' "$GITHUB_RELEASE_API" 2>/dev/null || true)"
	[ -n "$json" ] || return 1
	url="$(/usr/bin/osascript -l JavaScript \
		-e 'function run(a){try{var r=JSON.parse(a[0]),re=new RegExp("^fs-support-[0-9.]+-macos-"+a[1]+"\\.dmg$"),l=r.assets||[];for(var i=0;i<l.length;i++){if(re.test(l[i].name))return l[i].browser_download_url;}}catch(e){}return "";}' \
		"$json" "$ARCH" 2>/dev/null || true)"
	if [ -z "$url" ]; then
		url="$(printf '%s' "$json" | tr ',' '\n' |
			sed -n 's#.*"browser_download_url"[[:space:]]*:[[:space:]]*"\(https://[^"]*/fs-support-[0-9.]*-macos-'"$ARCH"'\.dmg\)".*#\1#p' || true)"
		url="${url%%$'\n'*}"
	fi
	case "$url" in
	https://*) ;;
	*) return 1 ;;
	esac
	DMG_URL="$url"
	VERSION="$(basename "$url" | sed -n 's/^fs-support-\([0-9.]*\)-macos-.*/\1/p' || true)"
	return 0
}

# Processus de l'interface : le service (--server, --service) porte le même nom, on l'écarte.
gui_pids() {
	local pid args
	for pid in $(pgrep -x "$APP_NAME" 2>/dev/null || true); do
		args="$(ps -o args= -p "$pid" 2>/dev/null || true)"
		case "$args" in
		*" --server"* | *" --service"*) continue ;;
		esac
		echo "$pid"
	done
}

quit_app() {
	local pid i=0
	[ -n "$(gui_pids)" ] || return 0
	info "Fermeture de FS Support…"
	/usr/bin/osascript -e 'ignoring application responses' -e "tell application \"$APP_NAME\" to quit" \
		-e 'end ignoring' >/dev/null 2>&1 || true
	while [ -n "$(gui_pids)" ] && [ "$i" -lt 20 ]; do
		sleep 0.5
		i=$((i + 1))
	done
	# Dernier recours : arrêt des seuls processus de l'interface (un pkill -x toucherait aussi le service).
	if [ -n "$(gui_pids)" ]; then
		note "FS Support ne se ferme pas : arrêt forcé."
		for pid in $(gui_pids); do kill "$pid" 2>/dev/null || true; done
		sleep 1
		for pid in $(gui_pids); do kill -9 "$pid" 2>/dev/null || true; done
	fi
}

# sudo seulement si l'utilisateur ne peut pas écrire lui-même dans /Applications (ou dans l'ancienne copie).
needs_admin() {
	[ -w /Applications ] || return 0
	if [ -e "$DEST" ]; then
		[ -w "$DEST" ] || return 0
		[ -z "$(find "$DEST" ! -user "$(id -u)" -print 2>/dev/null | head -n 1 || true)" ] || return 0
	fi
	return 1
}

as_admin() {
	if [ "$USE_SUDO" = 1 ]; then
		sudo "$@"
	else
		"$@"
	fi
}

signature_info() { /usr/bin/codesign -dvvv "$1" 2>&1 || true; }

cdhash() { signature_info "$1" | awk -F= '/^CDHash=/ { print $2; exit }' || true; }

# Le service « accès sans surveillance » (agent de lancement) tourne à part : on l'arrête, launchd le relance
# aussitôt avec la nouvelle version (KeepAlive). On attend son retour pour que l'interface s'y raccroche.
restart_agent() {
	local server="$DEST/Contents/MacOS/$APP_NAME --server" i=0
	pgrep -f "^$server" >/dev/null 2>&1 || return 0
	note "Redémarrage du service FS Support…"
	pkill -f "^$server" 2>/dev/null || true
	sleep 1
	while ! pgrep -f "^$server" >/dev/null 2>&1 && [ "$i" -lt 25 ]; do
		sleep 0.4
		i=$((i + 1))
	done
}

main() {
	local dmg src_app old_cdhash="" new_cdhash bundle_id service

	[ "$(uname -s)" = "Darwin" ] || fail "Ce script s'utilise sur un Mac."
	[ "$(id -u)" -ne 0 ] || fail "Lancez la commande sans « sudo » : le mot de passe sera demandé seulement si besoin."

	trap cleanup EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM

	printf '\033[1mFS Support — installation sur ce Mac\033[0m\n'

	detect_arch
	if [ "$ARCH" = "aarch64" ]; then
		note "Processeur : Apple Silicon"
	else
		note "Processeur : Intel"
	fi

	info "Recherche de la dernière version…"
	find_dmg_url || fail "Impossible de trouver FS Support en ligne. Vérifiez la connexion Internet puis relancez la commande."
	[ -z "$VERSION" ] || note "Version $VERSION"

	WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fs-support.XXXXXX")"
	dmg="$WORK_DIR/FS-Support.dmg"
	MOUNT_POINT="$WORK_DIR/image"

	info "Téléchargement…"
	curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --progress-bar -o "$dmg" "$DMG_URL" ||
		fail "Téléchargement interrompu. Vérifiez la connexion Internet puis relancez la commande."
	hdiutil imageinfo "$dmg" >/dev/null 2>&1 || fail "Le fichier téléchargé n'est pas une image disque valide."

	info "Ouverture de l'image disque…"
	mkdir -p "$MOUNT_POINT"
	hdiutil attach -nobrowse -noautoopen -quiet -mountpoint "$MOUNT_POINT" "$dmg" </dev/null ||
		fail "Impossible d'ouvrir l'image disque."
	MOUNTED=1
	src_app="$MOUNT_POINT/${APP_NAME}.app"
	if [ ! -d "$src_app" ]; then
		src_app="$(find "$MOUNT_POINT" -maxdepth 1 -type d -name '*.app' | head -n 1 || true)"
	fi
	[ -n "$src_app" ] && [ -d "$src_app" ] || fail "L'application est introuvable dans l'image disque."

	if needs_admin; then
		USE_SUDO=1
		info "Le dossier Applications est protégé : macOS demande le mot de passe de ce Mac."
		note "C'est le mot de passe de votre session (compte administrateur)."
		note "Rien ne s'affiche pendant la saisie, c'est normal : tapez-le puis appuyez sur Entrée."
		sudo -v </dev/tty || fail "Mot de passe refusé : il faut celui d'un compte administrateur de ce Mac."
	fi

	[ -d "$DEST" ] && old_cdhash="$(cdhash "$DEST")"
	quit_app

	info "Installation dans le dossier Applications…"
	as_admin rm -rf "$DEST" || fail "Impossible de retirer l'ancienne version de $DEST."
	as_admin /usr/bin/ditto "$src_app" "$DEST" || fail "Copie impossible vers $DEST."
	detach_image

	as_admin /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

	info "Vérification de la signature…"
	if /usr/bin/codesign --verify --deep --strict "$DEST" >/dev/null 2>&1; then
		note "Signature valide."
	else
		note "Signature incohérente : nouvelle signature locale (ad hoc)."
		as_admin /usr/bin/codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 ||
			fail "Impossible de signer $DEST."
		/usr/bin/codesign --verify --deep --strict "$DEST" >/dev/null 2>&1 ||
			fail "La signature de $DEST reste invalide."
		note "Signature refaite."
	fi
	# Copie faite en administrateur : rendue à l'utilisateur, la mise à jour intégrée n'aura pas à le redemander.
	if [ "$USE_SUDO" = 1 ]; then
		sudo chown -R "$(id -un):staff" "$DEST" 2>/dev/null || true
	fi

	# Signature ad hoc : macOS lie Accessibilité et Enregistrement de l'écran à l'empreinte exacte de
	# l'application. Après une mise à jour, l'ancienne case reste cochée mais ne sert plus à rien : on la
	# retire pour que FS Support la redemande proprement.
	new_cdhash="$(cdhash "$DEST")"
	if [ -n "$old_cdhash" ] && [ "$old_cdhash" != "$new_cdhash" ]; then
		case "$(signature_info "$DEST")" in
		*"Signature=adhoc"*)
			bundle_id="$(/usr/bin/defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
			if [ -n "$bundle_id" ]; then
				note "Nouvelle version : les autorisations macOS seront redemandées à l'ouverture."
				for service in Accessibility ScreenCapture ListenEvent; do
					/usr/bin/tccutil reset "$service" "$bundle_id" >/dev/null 2>&1 || true
				done
			fi
			;;
		esac
	fi

	restart_agent
	if grep -qs "$DEST" /Library/LaunchDaemons/*.plist; then
		note "Le service système de FS Support passera à la nouvelle version au prochain redémarrage du Mac."
	fi

	info "Ouverture de FS Support…"
	open "$DEST" || fail "FS Support est installé mais ne s'ouvre pas : ouvrez-le depuis le dossier Applications."

	printf '\n\033[1mFS Support est installé%s.\033[0m\n' "${VERSION:+ (version $VERSION)}"
	note "À la première ouverture, FS Support vous guide pour donner deux autorisations à macOS :"
	note "  - Accessibilité : pour cliquer et écrire sur ce Mac à distance ;"
	note "  - Enregistrement de l'écran : pour voir l'écran de ce Mac à distance."
	note "Vous pouvez fermer ce Terminal."
}

main "$@"
