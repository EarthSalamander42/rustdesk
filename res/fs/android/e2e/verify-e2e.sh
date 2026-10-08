#!/usr/bin/env bash
# FS Support — verification e2e de l'acces direct (sur emulateur GitHub Actions UNIQUEMENT).
#
# Lance acces-direct.sh EXACTEMENT comme Jason (adb push + adb shell sh), puis verifie et
# rapporte en annotations (::notice:: / ::error:: / ::warning::, 10 au plus par etape).
# Essentiel (fait echouer le job) : appops, WRITE_SECURE_SETTINGS, accessibilite, reactivation auto.
# Non essentiel (rapporte seulement) : capture sans fenetre (plomberie root/prefs, limite Android 14+).
#
# Variables : API_LEVEL (niveau d'API), E2E_OUT (dossier d'artefacts).
set -u

PKG="fr.fssolutions.support"
SERVICE="$PKG/com.carriez.flutter_hbb.InputService"
BOOT_ACTION="fr.fssolutions.support.DEBUG_BOOT_COMPLETED"
API="${API_LEVEL:-0}"
OUT="${E2E_OUT:-e2e-artifacts}"
mkdir -p "$OUT"

FAIL=0
essential_fail() { echo "::error::[API $API] $1"; FAIL=1; }
notice() { echo "::notice::[API $API] $1"; }
warn() { echo "::warning::[API $API] $1"; }

# adb shell en nettoyant les retours chariot Windows.
ash() { adb shell "$@" 2>/dev/null | tr -d '\r'; }

echo "=== FS Support e2e (API $API) ==="

adb wait-for-device
# Attendre la fin du boot.
n=0
while [ "$(ash getprop sys.boot_completed)" != "1" ]; do
  n=$((n + 1)); [ "$n" -gt 120 ] && break; sleep 1
done
adb shell input keyevent 82 >/dev/null 2>&1 || true
REL="$(ash getprop ro.build.version.release)"
notice "Emulateur pret : Android $REL (API $API)"

# ---- Installation de l'APK FS Support ----
APK="$(ls apk/*.apk 2>/dev/null | head -n 1)"
if [ -z "$APK" ]; then
  essential_fail "APK FS Support introuvable (artefact fs-support-apk)"
else
  echo "APK : $APK"
  if ! adb install -r -g "$APK" >/dev/null 2>&1; then
    adb install -r "$APK" >/dev/null 2>&1 || essential_fail "Installation de l'APK en echec"
  fi
fi

# ---- Preparation : acces-direct.sh, exactement comme le ferait Jason ----
adb push res/fs/android/acces-direct.sh /data/local/tmp/acces-direct.sh >/dev/null 2>&1
echo "--- acces-direct.sh ---"
adb shell sh /data/local/tmp/acces-direct.sh 2>&1 | tee "$OUT/acces-direct-$API.log"
echo "--- fin acces-direct.sh ---"

# ================= Verifications essentielles =================

# A. appops PROJECT_MEDIA et SYSTEM_ALERT_WINDOW = allow
PM="$(ash appops get "$PKG" PROJECT_MEDIA)"
case "$PM" in
  *allow*) notice "PROJECT_MEDIA = allow (capture sans fenetre autorisee)" ;;
  *) essential_fail "PROJECT_MEDIA != allow : ${PM:-vide}" ;;
esac
SAW="$(ash appops get "$PKG" SYSTEM_ALERT_WINDOW)"
case "$SAW" in
  *allow*) notice "SYSTEM_ALERT_WINDOW = allow (fenetre par-dessus)" ;;
  *) essential_fail "SYSTEM_ALERT_WINDOW != allow : ${SAW:-vide}" ;;
esac

# B. WRITE_SECURE_SETTINGS accordee
# dumpsys package liste la permission DEUX fois : dans « requested permissions » (sans etat) et dans
# « install permissions » (avec « granted=true/false »). On ne garde que la ligne d'etat, sinon la
# ligne « requested » (la premiere) faisait echouer le test a tort.
WSS="$(ash dumpsys package "$PKG" | grep WRITE_SECURE_SETTINGS | grep granted= | head -n 1)"
case "$WSS" in
  *granted=true*) notice "WRITE_SECURE_SETTINGS accordee" ;;
  *) essential_fail "WRITE_SECURE_SETTINGS non accordee : ${WSS:-absente}" ;;
esac

# C. Service d'accessibilite present (liste + drapeau global)
EAS="$(ash settings get secure enabled_accessibility_services)"
AEN="$(ash settings get secure accessibility_enabled)"
case ":$EAS:" in
  *":$SERVICE:"*) ACC_IN_LIST=1 ;;
  *) ACC_IN_LIST=0 ;;
esac
if [ "$ACC_IN_LIST" = 1 ] && [ "$AEN" = "1" ]; then
  notice "Service d'accessibilite present et active"
else
  essential_fail "Accessibilite non activee par le script (liste='$EAS' enabled='$AEN')"
fi
ash dumpsys accessibility > "$OUT/dumpsys-accessibility-$API.txt" 2>&1 || true
if grep -q "com.carriez.flutter_hbb.InputService" "$OUT/dumpsys-accessibility-$API.txt" 2>/dev/null; then
  notice "dumpsys accessibility mentionne le service FS Support"
fi

# E. Reactivation automatique : on desactive l'accessibilite puis on simule le boot.
ash settings put secure enabled_accessibility_services "" >/dev/null 2>&1
ash settings put secure accessibility_enabled 0 >/dev/null 2>&1
sleep 3  # laisser le systeme delier le service (InputService.isOpen -> false)
REACT=0
i=0
while [ "$i" -lt 15 ]; do
  # Rediffuse a chaque tour : evite la course ou le service n'est pas encore delie au 1er envoi.
  adb shell am broadcast -a "$BOOT_ACTION" -p "$PKG" >/dev/null 2>&1
  sleep 2
  EAS2="$(ash settings get secure enabled_accessibility_services)"
  case ":$EAS2:" in
    *":$SERVICE:"*) REACT=1; break ;;
  esac
  i=$((i + 1))
done
if [ "$REACT" = 1 ]; then
  notice "Reactivation automatique de l'accessibilite confirmee (WRITE_SECURE_SETTINGS)"
else
  essential_fail "Reactivation automatique KO : service absent apres rebroadcast (liste='${EAS2:-vide}')"
fi

# ================= Verifications non essentielles =================

# F. Capture active SANS fenetre de consentement (demarrage au boot).
#    Necessite d'activer « demarrage au boot » : on ecrit la preference en root (emulateur google_apis).
prepare_start_on_boot() {
  adb root >/dev/null 2>&1 || return 1
  adb wait-for-device
  sleep 3
  cat > /tmp/kss.xml <<'XML'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="KEY_START_ON_BOOT_OPT" value="true" />
</map>
XML
  adb push /tmp/kss.xml /data/local/tmp/kss.xml >/dev/null 2>&1 || return 1
  local datadir="/data/data/$PKG"
  local prefsdir="$datadir/shared_prefs"
  adb shell "mkdir -p $prefsdir" >/dev/null 2>&1 || return 1
  adb shell "cp /data/local/tmp/kss.xml $prefsdir/KEY_SHARED_PREFERENCES.xml" >/dev/null 2>&1 || return 1
  local u
  u="$(ash stat -c %u "$datadir")"
  if [ -n "$u" ]; then
    adb shell "chown $u:$u $prefsdir $prefsdir/KEY_SHARED_PREFERENCES.xml" >/dev/null 2>&1 || true
  fi
  adb shell "chmod 771 $prefsdir; chmod 660 $prefsdir/KEY_SHARED_PREFERENCES.xml" >/dev/null 2>&1 || true
  adb shell "restorecon -R $prefsdir" >/dev/null 2>&1 || true
  return 0
}

if prepare_start_on_boot; then
  adb shell dumpsys deviceidle whitelist "+$PKG" >/dev/null 2>&1 || true
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  sleep 1
  adb shell am broadcast -a "$BOOT_ACTION" -p "$PKG" >/dev/null 2>&1
  CAPOK=0
  i=0
  while [ "$i" -lt 20 ]; do
    MP="$(ash dumpsys media_projection)"
    case "$MP" in
      *"$PKG"*) CAPOK=1; break ;;
    esac
    i=$((i + 1)); sleep 2
  done
  WIN="$(ash dumpsys window | grep -i MediaProjectionPermission | head -n 1)"
  ash dumpsys media_projection > "$OUT/media_projection-$API.txt" 2>&1 || true
  if [ "$CAPOK" = 1 ] && [ -z "$WIN" ]; then
    notice "Capture active SANS fenetre de consentement (projection detenue par $PKG)"
  elif [ "$API" -ge 34 ]; then
    warn "API $API : capture sans fenetre NON confirmee — limite Android 14+ connue et documentee"
  else
    warn "Capture sans fenetre non confirmee (projection=$CAPOK, fenetre_consentement='${WIN:-aucune}')"
  fi
else
  warn "Demarrage au boot non prepare (root/prefs indisponibles) : verification capture ignoree"
fi

# Option « Clics compatibles ecrans interactifs » : sans session distante on ne peut pas
# emettre de geste reel par InputService (adb input tap ne passe pas par le service). On
# verifie donc le pipeline de journalisation « FS Support » et on documente la limite.
if adb logcat -d 2>/dev/null | grep -q "FS Support"; then
  notice "Journalisation « FS Support » presente (mode clics forces valide a la compilation ; exercice reel = session distante)"
else
  warn "Aucune ligne de log « FS Support » captee (option clics forces validee a la compilation)"
fi

# ---- Artefacts ----
adb logcat -d > "$OUT/logcat-$API.txt" 2>&1 || true
adb exec-out screencap -p > "$OUT/screen-$API.png" 2>/dev/null || true
ash dumpsys window > "$OUT/dumpsys-window-$API.txt" 2>&1 || true

echo "=== Fin e2e (API $API) : $( [ "$FAIL" = 0 ] && echo OK || echo ECHEC ) ==="
if [ "$FAIL" = 0 ]; then
  echo "::notice::[API $API] FS Support acces direct : toutes les verifications essentielles sont au vert"
else
  echo "::error::[API $API] FS Support acces direct : au moins une verification essentielle a echoue"
fi
exit "$FAIL"
