#!/usr/bin/env bash
# FS Support — contrôle du service macOS (LaunchDaemon + LaunchAgent) sur le runner de la CI, jamais sur un
# Mac client. Lancé après l'installation du .pkg (verifier-pkg.sh), app dans /Applications/FS Support.app.
#
# Usage : bash res/fs/macos/verifier-service.sh <rapport.txt>
#
# 1. `service --write-plists` (code Rust réel) : plists aux NOUVEAUX noms, sans espace, valides (plutil) ;
# 2. anciens fichiers plantés (com.carriez.FS Support_*.plist et com.carriez.FS tronqué) ;
# 3. installation par le vrai chemin de l'app : AppleScript de src/platform/macos.rs (osascript, en root
#    pour éviter la fenêtre du mot de passe) + common.sh + install.sh → anciens fichiers nettoyés,
#    `launchctl print system/<service>` OK, agent chargé dans la session graphique si elle existe ;
# 4. 40 s d'observation : nombre de lancements du service (relances en rafale = échec) ;
# 5. désinstallation (uninstall.sh) : plists retirés, plus rien dans launchctl.
set -uo pipefail

RAPPORT="${1:?fichier de rapport manquant}"
APP_NAME="FS Support"
APP="/Applications/${APP_NAME}.app"
PREFIX="fr.fs-solutions.support"
D_LABEL="${PREFIX}_service"
A_LABEL="${PREFIX}_server"
D_PLIST="/Library/LaunchDaemons/${D_LABEL}.plist"
A_PLIST="/Library/LaunchAgents/${A_LABEL}.plist"
SCRIPTS="src/platform/privileges_scripts"
erreurs=0

exec > >(tee "$RAPPORT") 2>&1
ok() { echo "OK      $*"; }
ko() { echo "ÉCHEC   $*"; echo "::error title=Service macOS::$*"; erreurs=$((erreurs + 1)); }
info() { echo "INFO    $*"; }

[ -x "$APP/Contents/MacOS/service" ] || { ko "$APP/Contents/MacOS/service absent"; exit 1; }
UTIL="$(id -un)"
UID_UTIL="$(id -u)"
info "macOS $(sw_vers -productVersion), utilisateur $UTIL ($UID_UTIL)"

echo "== 1. service --write-plists (rendu Rust des modèles)"
if sudo perl -e 'alarm 60; exec @ARGV' "$APP/Contents/MacOS/service" --write-plists; then ok "--write-plists"; else ko "--write-plists a échoué"; fi
for f in "$D_PLIST" "$A_PLIST"; do
	if [ -f "$f" ] && plutil -lint -s "$f" >/dev/null; then ok "$f présent et valide"; else ko "$f absent ou invalide"; fi
done
ls -l /Library/LaunchDaemons/ /Library/LaunchAgents/ | grep -iE "carriez|fs-solutions" | sed 's/^/  /'
if ls /Library/LaunchDaemons/ /Library/LaunchAgents/ | grep -q " "; then ko "un nom de plist contient une espace"; else ok "aucun nom de plist avec espace"; fi
[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$D_PLIST" 2>/dev/null)" = "$D_LABEL" ] && ok "étiquette $D_LABEL" || ko "étiquette du service"
[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$A_PLIST" 2>/dev/null)" = "$A_LABEL" ] && ok "étiquette $A_LABEL" || ko "étiquette de l'agent"
info "service : $(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$D_PLIST" 2>/dev/null)"
info "agent   : $(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$A_PLIST" 2>/dev/null)"
DAEMON_BODY="$(cat "$D_PLIST")"
AGENT_BODY="$(cat "$A_PLIST")"
sudo rm -f "$D_PLIST" "$A_PLIST"

echo "== 2. Anciens fichiers plantés (noms avec espace, et forme tronquée de l'ancien script)"
for f in "/Library/LaunchDaemons/com.carriez.FS Support_service.plist" "/Library/LaunchAgents/com.carriez.FS Support_server.plist" \
	"/Library/LaunchDaemons/com.carriez.FS" "/Library/LaunchAgents/com.carriez.FS"; do
	printf '%s\n' "$DAEMON_BODY" | sudo tee "$f" >/dev/null && info "planté : $f"
done

echo "== 3. Installation par l'AppleScript de l'app (osascript en root, sans fenêtre)"
RUNNER="$(awk '/^const FS_PRIVILEGED_RUNNER/{on=1; sub(/.*r#"/, ""); print; next} on && /^end run"#;/{print "end run"; exit} on{print}' src/platform/macos.rs)"
[ -n "$RUNNER" ] && info "AppleScript extrait ($(printf '%s\n' "$RUNNER" | wc -l | tr -d ' ') lignes)" || ko "AppleScript introuvable dans macos.rs"
SCRIPT="$(cat "$SCRIPTS/common.sh"; echo; cat "$SCRIPTS/install.sh")"
CONF_DIR="$HOME/Library/Preferences/fs-test"
mkdir -p "$CONF_DIR" && echo "id = 'essai'" >"$CONF_DIR/${APP_NAME}.toml"
LEGACY=("com.carriez.FS Support_service|/Library/LaunchDaemons/com.carriez.FS Support_service.plist"
	"com.carriez.FS Support_server|/Library/LaunchAgents/com.carriez.FS Support_server.plist"
	"com.carriez.FS|/Library/LaunchDaemons/com.carriez.FS" "com.carriez.FS|/Library/LaunchAgents/com.carriez.FS")
if sudo perl -e 'alarm 120; exec @ARGV' /usr/bin/osascript -e "$RUNNER" "$SCRIPT" "FS Support doit installer son service de prise en main." \
	"$DAEMON_BODY" "$AGENT_BODY" "$UTIL" "$D_PLIST" "$A_PLIST" "$D_LABEL" "$A_LABEL" \
	"$CONF_DIR/${APP_NAME}.toml" "$CONF_DIR/${APP_NAME}2.toml" "/var/root/Library/Preferences/fs-test" "${LEGACY[@]}"; then
	ok "install.sh via osascript"
else
	ko "install.sh via osascript (code $?)"
fi
for e in "${LEGACY[@]}"; do
	f="${e#*|}"
	[ -e "$f" ] && ko "ancien fichier non nettoyé : $f" || ok "ancien fichier retiré : $f"
done
sudo test -f "/var/root/Library/Preferences/fs-test/${APP_NAME}.toml" && ok "configuration copiée pour root" || ko "configuration non copiée pour root"
sudo rm -rf /var/root/Library/Preferences/fs-test "$CONF_DIR"
if sudo launchctl print "system/$D_LABEL" >/tmp/fs-d.txt 2>&1; then
	ok "launchctl print system/$D_LABEL"
	grep -E '^[[:space:]]*(state|pid|runs|last exit code|program) ' /tmp/fs-d.txt | sed 's/^/  /'
else
	ko "service $D_LABEL absent de launchctl"
	sed 's/^/  /' /tmp/fs-d.txt
fi
if launchctl print "gui/$UID_UTIL/$A_LABEL" >/tmp/fs-a.txt 2>&1; then
	ok "agent chargé dans gui/$UID_UTIL"
	grep -E '^[[:space:]]*(state|pid|runs|last exit code) ' /tmp/fs-a.txt | sed 's/^/  /'
else
	info "agent absent de gui/$UID_UTIL (session graphique du runner indisponible ?) : $(head -n 2 /tmp/fs-a.txt | tr '\n' ' ')"
fi
launchctl list | grep -i "fs-solutions" | sed 's/^/  launchctl list : /' || true

echo "== 4. Observation 40 s (relances en rafale ?)"
runs_debut="$(sudo launchctl print "system/$D_LABEL" 2>/dev/null | awk '/^[[:space:]]*runs = /{print $3; exit}')"
sleep 40
sudo launchctl print "system/$D_LABEL" >/tmp/fs-d2.txt 2>&1
runs_fin="$(awk '/^[[:space:]]*runs = /{print $3; exit}' /tmp/fs-d2.txt)"
etat="$(awk '/^[[:space:]]*state = /{print $3; exit}' /tmp/fs-d2.txt)"
info "service : runs ${runs_debut:-?} → ${runs_fin:-?}, état ${etat:-?}"
if [ -n "${runs_fin:-}" ] && [ "${runs_fin}" -le "$(( ${runs_debut:-0} + 1 ))" ]; then ok "pas de relance en boucle du service"; else ko "le service redémarre en boucle (runs ${runs_debut:-?} → ${runs_fin:-?})"; fi
[ "${etat:-}" = "running" ] && ok "service en marche" || info "service non « running » sur le runner (état ${etat:-?})"
a_runs="$(launchctl print "gui/$UID_UTIL/$A_LABEL" 2>/dev/null | awk '/^[[:space:]]*runs = /{print $3; exit}')"
[ -n "$a_runs" ] && info "agent : runs $a_runs"
pgrep -fl "${APP_NAME}.app/Contents/MacOS" | sed 's/^/  processus : /' || true
sudo tail -n 20 "/var/log/fs-support_service.err" 2>/dev/null | sed 's/^/  service.err : /' || true

echo "== 5. Désinstallation (uninstall.sh via osascript)"
SCRIPT_U="$(cat "$SCRIPTS/common.sh"; echo; cat "$SCRIPTS/uninstall.sh")"
if sudo perl -e 'alarm 120; exec @ARGV' /usr/bin/osascript -e "$RUNNER" "$SCRIPT_U" "FS Support doit retirer son service." \
	"$UTIL" "$D_LABEL|$D_PLIST" "$A_LABEL|$A_PLIST" "${LEGACY[@]}"; then ok "uninstall.sh"; else ko "uninstall.sh (code $?)"; fi
[ -e "$D_PLIST" ] || [ -e "$A_PLIST" ] && ko "plists encore présents" || ok "plists retirés"
sudo launchctl print "system/$D_LABEL" >/dev/null 2>&1 && ko "service encore chargé" || ok "service déchargé"
launchctl print "gui/$UID_UTIL/$A_LABEL" >/dev/null 2>&1 && ko "agent encore chargé" || ok "agent déchargé"

echo "== Bilan : $erreurs échec(s)"
exit $(( erreurs > 0 ? 1 : 0 ))
