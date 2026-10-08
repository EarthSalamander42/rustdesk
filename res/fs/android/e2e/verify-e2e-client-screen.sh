#!/usr/bin/env bash
# FS Support — verification e2e du mode « Ecran client » (emulateur GitHub Actions UNIQUEMENT).
#
# Cas du client SANS ADB : PROJECT_MEDIA n'est PAS pre-pose (pas d'ADB pour le faire). On active
# l'accessibilite par « settings put » et le mode « Ecran client » par les options (SharedPreferences,
# ecrites en root), car l'emulateur n'a personne pour toucher l'ecran ; on pose la superposition
# (etape de l'assistant). On simule le boot : le service doit demander la capture et la fenetre
# systeme de consentement doit s'ouvrir.
#
# Essentiel (fait echouer le job) : mode actif, accessibilite liee, et le chemin boot -> service ->
# demande de capture (projection active OU fenetre de consentement ouverte au boot).
# NON essentiel (rapporte seulement) : l'auto-clic du consentement par l'accessibilite, car le
# dialogue systeme MediaProjectionPermissionActivity n'expose pas son contenu a l'accessibilite sur
# l'emulateur (nœuds non lisibles) — a verifier sur un vrai ecran (ROM Droidlogic). Idem pour
# l'auto-validation de l'installateur de mise a jour (voir la limite versionCode en CI).
#
# Variables : API_LEVEL, E2E_OUT.
set -u

PKG="fr.fssolutions.support"
SERVICE="$PKG/com.carriez.flutter_hbb.InputService"
BOOT_ACTION="fr.fssolutions.support.DEBUG_BOOT_COMPLETED"
INSTALL_ACTION="fr.fssolutions.support.DEBUG_INSTALL_APK"
API="${API_LEVEL:-0}"
OUT="${E2E_OUT:-e2e-artifacts}"
mkdir -p "$OUT"

FAIL=0
essential_fail() { echo "::error::[API $API] $1"; FAIL=1; }
notice() { echo "::notice::[API $API] $1"; }
warn() { echo "::warning::[API $API] $1"; }
ash() { adb shell "$@" 2>/dev/null | tr -d '\r'; }

echo "=== FS Support e2e Ecran client (API $API) ==="

adb wait-for-device
n=0
while [ "$(ash getprop sys.boot_completed)" != "1" ]; do
  n=$((n + 1)); [ "$n" -gt 120 ] && break; sleep 1
done
adb shell input keyevent 82 >/dev/null 2>&1 || true
REL="$(ash getprop ro.build.version.release)"
notice "Emulateur pret : Android $REL (API $API)"

# ---- Installation SANS -g (aucune permission d'office) ----
APK="$(ls apk/*.apk 2>/dev/null | head -n 1)"
if [ -z "$APK" ]; then
  essential_fail "APK FS Support introuvable (artefact fs-support-apk)"
  echo "=== Fin e2e Ecran client (API $API) : ECHEC ==="
  exit 1
fi
echo "APK : $APK"
adb install -r "$APK" >/dev/null 2>&1 || essential_fail "Installation de l'APK en echec"

# ---- Mode « Ecran client » + demarrage au boot : SharedPreferences ecrites en root ----
#      (l'app expose ce booleen via FsClientScreen ; en test on l'ecrit directement, sans l'UI).
prepare_client_screen_prefs() {
  adb root >/dev/null 2>&1 || return 1
  adb wait-for-device
  sleep 3
  cat > /tmp/kcs.xml <<'XML'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="KEY_START_ON_BOOT_OPT" value="true" />
    <boolean name="KEY_FS_CLIENT_SCREEN" value="true" />
</map>
XML
  adb push /tmp/kcs.xml /data/local/tmp/kcs.xml >/dev/null 2>&1 || return 1
  local datadir="/data/data/$PKG"
  local prefsdir="$datadir/shared_prefs"
  adb shell "mkdir -p $prefsdir" >/dev/null 2>&1 || return 1
  adb shell "cp /data/local/tmp/kcs.xml $prefsdir/KEY_SHARED_PREFERENCES.xml" >/dev/null 2>&1 || return 1
  local u
  u="$(ash stat -c %u "$datadir")"
  if [ -n "$u" ]; then
    adb shell "chown $u:$u $prefsdir $prefsdir/KEY_SHARED_PREFERENCES.xml" >/dev/null 2>&1 || true
  fi
  adb shell "chmod 771 $prefsdir; chmod 660 $prefsdir/KEY_SHARED_PREFERENCES.xml" >/dev/null 2>&1 || true
  adb shell "restorecon -R $prefsdir" >/dev/null 2>&1 || true
  return 0
}
if prepare_client_screen_prefs; then
  notice "Mode « Ecran client » activé (SharedPreferences)"
else
  essential_fail "Impossible d'écrire les SharedPreferences du mode Ecran client (root indisponible)"
fi

# ---- Accessibilite activee par settings put (personne pour toucher) ----
ash settings put secure enabled_accessibility_services "$SERVICE" >/dev/null 2>&1
ash settings put secure accessibility_enabled 1 >/dev/null 2>&1
# Attendre la liaison du service (onServiceConnected).
BOUND=0
i=0
while [ "$i" -lt 20 ]; do
  ash dumpsys accessibility | grep -q "com.carriez.flutter_hbb.InputService" && { BOUND=1; break; }
  i=$((i + 1)); sleep 1
done
if [ "$BOUND" = 1 ]; then
  notice "Service d'accessibilite FS Support lie"
else
  essential_fail "Service d'accessibilite non lie apres activation"
fi

# ---- PROJECT_MEDIA reste NON pose : c'est LE point du cas « client sans ADB ». La capture doit
#      donc ouvrir une fenetre de consentement, que le service d'accessibilite validera seul. ----
PM="$(ash appops get "$PKG" PROJECT_MEDIA)"
case "$PM" in
  *allow*) warn "PROJECT_MEDIA deja allow : le cas « sans pre-autorisation de capture » n'est pas represente" ;;
  *) notice "PROJECT_MEDIA non pose (pas de pre-autorisation de capture : cas client sans ADB)" ;;
esac

# Superposition (SYSTEM_ALERT_WINDOW) : etape que la personne coche dans l'assistant sur place.
# On l'emule ici (l'emulateur ne peut pas toucher l'ecran) car Android la demande pour qu'un service
# demarre au boot puisse ouvrir une activite (regle de lancement d'activite en arriere-plan) : sans
# elle, la fenetre de consentement de capture ne peut pas apparaitre. PROJECT_MEDIA, lui, reste NON pose.
ash appops set "$PKG" SYSTEM_ALERT_WINDOW allow >/dev/null 2>&1 || true

adb exec-out screencap -p > "$OUT/client-screen-avant-$API.png" 2>/dev/null || true

# ---- Simulation du boot : le service demande la capture, la fenetre de consentement est auto-validee.
#      PAS de « am force-stop » : un paquet « stoppe » ne recoit pas le broadcast de boot (le service
#      ne demarrerait jamais). Le processus est vivant (service d'accessibilite lie), donc le receiver
#      manifeste BootReceiver recoit bien l'action de boot simulee. ----
ash dumpsys deviceidle whitelist "+$PKG" >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
adb shell am broadcast -a "$BOOT_ACTION" -p "$PKG" >/dev/null 2>&1

CAPOK=0
i=0
while [ "$i" -lt 30 ]; do
  MP="$(ash dumpsys media_projection)"
  case "$MP" in
    *"$PKG"*) CAPOK=1; break ;;
  esac
  # Relance du boot a mi-parcours (robustesse : premiere diffusion parfois avant la fin de la liaison).
  [ "$i" = 8 ] && adb shell am broadcast -a "$BOOT_ACTION" -p "$PKG" >/dev/null 2>&1
  i=$((i + 1)); sleep 2
done
ash dumpsys media_projection > "$OUT/client-screen-media_projection-$API.txt" 2>&1 || true
adb exec-out screencap -p > "$OUT/client-screen-apres-$API.png" 2>/dev/null || true
WIN="$(ash dumpsys window | grep -i MediaProjectionPermission | head -n 1)"

# ESSENTIEL : le chemin boot -> service -> demande de capture doit fonctionner, c-a-d la projection
# active (auto-clic reussi) OU au moins la fenetre de consentement ouverte au boot.
# NON ESSENTIEL (rapporte seulement) : l'auto-clic lui-meme. Sur emulateur, le dialogue systeme
# MediaProjectionPermissionActivity n'expose pas son contenu a l'accessibilite (nœuds non lisibles),
# donc le service ne peut ni lire le libelle « FS Support » ni trouver le bouton : impossible de
# valider le clic ici. A verifier sur un vrai ecran (ROM Droidlogic), ou le dialogue est accessible.
CASE_LOG="$(adb logcat -d 2>/dev/null | grep -F 'FS Support' \
  | grep -iE 'consentement de capture valide|capture NON validee|capture fenetres' \
  | tail -n 1 | sed 's/.*FS Support : //; s/[^[:print:]]//g')"
if [ "$CAPOK" = 1 ]; then
  notice "Consentement de capture valide automatiquement : projection active pour $PKG"
  [ -n "$CASE_LOG" ] && notice "Journal : $CASE_LOG"
elif [ -n "$WIN" ]; then
  notice "Boot -> service -> demande de capture OK : fenetre de consentement ouverte au boot (MediaProjectionPermissionActivity)"
  warn "Auto-clic du consentement NON confirme sur emulateur : le dialogue systeme n'expose pas ses nœuds a l'accessibilite. A verifier sur le vrai ecran Droidlogic."
  [ -n "$CASE_LOG" ] && warn "Diagnostic auto-clic (dernier cas vu par le service) : $CASE_LOG"
else
  essential_fail "Capture NON demarree au boot : ni projection active ni fenetre de consentement (chemin boot -> service -> demande de capture casse)"
fi

# ================= Non essentiel : auto-validation de l'installateur de mise a jour =================
# Limite CI connue : on ne reconstruit pas un 2e APK a versionCode superieur (le build Android FS est
# deja long ; un 2e passage doublerait la nuit). On reinstalle donc le MEME APK pour exercer le clic
# automatique de l'installateur. Un versionCode identique peut ne pas declencher de fenetre de
# confirmation selon la ROM : ce controle est donc rapporte, jamais bloquant.
UP_DIR="/storage/emulated/0/Android/data/$PKG/files/updates"
UP_APK="$UP_DIR/fs-support-update.apk"
adb shell "mkdir -p $UP_DIR" >/dev/null 2>&1 || true
adb push "$APK" "$UP_APK" >/dev/null 2>&1 || true
# Autoriser l'installation de sources inconnues pour l'app.
ash appops set "$PKG" REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
adb shell am broadcast -a "$INSTALL_ACTION" -p "$PKG" --es path "$UP_APK" >/dev/null 2>&1 || true
INSTOK=0
i=0
while [ "$i" -lt 20 ]; do
  L="$(adb logcat -d 2>/dev/null | grep -iF 'installation de la mise a jour' | head -n 1)"
  [ -z "$L" ] && L="$(adb logcat -d 2>/dev/null | grep -iF 'installateur de mise a jour lance' | head -n 1)"
  if [ -n "$L" ]; then INSTOK=1; break; fi
  i=$((i + 1)); sleep 2
done
adb exec-out screencap -p > "$OUT/client-screen-maj-$API.png" 2>/dev/null || true
if [ "$INSTOK" = 1 ]; then
  notice "Installateur de mise a jour lance et/ou valide automatiquement (journal present)"
else
  warn "Auto-validation de l'installateur NON confirmee (limite CI : pas de 2e APK a versionCode superieur ; reinstallation identique parfois sans fenetre)"
fi

# ---- Artefacts ----
adb logcat -d > "$OUT/client-screen-logcat-$API.txt" 2>&1 || true
ash dumpsys window > "$OUT/client-screen-window-$API.txt" 2>&1 || true

echo "=== Fin e2e Ecran client (API $API) : $( [ "$FAIL" = 0 ] && echo OK || echo ECHEC ) ==="
if [ "$FAIL" = 0 ]; then
  echo "::notice::[API $API] FS Support mode Ecran client : essentiels au vert (mode actif, accessibilite liee, et au boot la demande de capture ouvre bien la fenetre de consentement). L'auto-clic du dialogue n'est pas verifiable sur emulateur (dialogue systeme non expose a l'accessibilite) : voir les warnings."
else
  echo "::error::[API $API] FS Support mode Ecran client : au moins une verification essentielle a echoue"
fi
exit "$FAIL"
