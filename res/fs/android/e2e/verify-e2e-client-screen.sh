#!/usr/bin/env bash
# FS Support — verification e2e du mode « Ecran client » (emulateur GitHub Actions UNIQUEMENT).
#
# Cas du client SANS ADB : PROJECT_MEDIA n'est PAS pre-pose (pas d'ADB pour le faire). On active
# l'accessibilite par « settings put » et le mode « Ecran client » par les options (SharedPreferences,
# ecrites en root), car l'emulateur n'a personne pour toucher l'ecran ; on pose la superposition
# (etape de l'assistant). On simule le boot : le service doit demander la capture et la fenetre
# systeme de consentement doit s'ouvrir.
#
# Essentiel (fait echouer le job) : mode actif, accessibilite liee, et au boot le consentement de
# capture est VALIDE automatiquement par le service (projection active) — le bouton positif etant
# cible par identifiant connu ou par texte (cliquable), hors libelles negatifs. BLOQUANT sur API<=33.
# Sur API>=34, le dialogue systeme de l'emulateur n'expose que « Cancel » a l'accessibilite (le
# bouton positif n'est pas un nœud accessible) : l'auto-validation y est donc RAPPORTEE sans bloquer,
# a confirmer sur un vrai ecran (ROM Droidlogic).
# NON essentiel (rapporte seulement) : l'auto-validation de l'installateur de mise a jour (limite
# CI : pas de 2e APK a versionCode superieur).
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

# ESSENTIEL : le consentement de capture doit etre valide automatiquement au boot (projection active).
# Diagnostic remonte en annotations : dernier cas (a/b/c) vu par le service + enumeration des fenetres
# (paquet, titre, racine lisible, textes, nœuds cliquables id+texte) pour cibler le bouton.
CASE_LOG="$(adb logcat -d 2>/dev/null | grep -F 'FS Support' \
  | grep -iE 'consentement de capture valide|capture NON validee|capture fenetres' \
  | tail -n 1 | sed 's/.*FS Support : //; s/[^[:print:]]//g')"
if [ "$CAPOK" = 1 ]; then
  notice "Consentement de capture valide automatiquement : projection active pour $PKG"
  [ -n "$CASE_LOG" ] && notice "Journal : $CASE_LOG"
elif [ "$API" -ge 34 ]; then
  # Limite connue de l'emulateur API 34 : le dialogue systeme n'expose a l'accessibilite que le
  # bouton « Cancel » (le bouton positif « Start » n'est pas un nœud accessible). Le ciblage du
  # bouton est pourtant correct (verifie sur API 33, ou il aboutit). A confirmer sur le vrai ecran
  # Droidlogic. On rapporte donc sans bloquer sur API 34+.
  [ -n "$WIN" ] && notice "Fenetre de consentement ouverte au boot ; auto-clic non confirme sur emulateur API $API"
  [ -n "$CASE_LOG" ] && warn "Diagnostic (fenetres/nœuds cliquables vus par le service) : $CASE_LOG"
  warn "API $API : bouton positif du dialogue non expose a l'accessibilite sur cet emulateur (seul « Cancel » l'est). A verifier sur le vrai ecran Droidlogic. Auto-clic OK sur API 33."
else
  [ -n "$WIN" ] && notice "Fenetre de consentement ouverte au boot (MediaProjectionPermissionActivity), mais auto-clic non abouti"
  [ -n "$CASE_LOG" ] && warn "Diagnostic (dernier cas / fenetres vues par le service) : $CASE_LOG"
  essential_fail "Consentement de capture NON valide automatiquement au boot (fenetre='${WIN:-aucune}')"
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

# ================= Journal de plantage + relance automatique du partage (14/10/2026) =================
# Un plantage est provoque (« am crash ») : le gestionnaire d'exceptions doit ecrire la pile, le systeme
# relance le processus pour le service d'accessibilite, le mode Ecran client doit RELANCER le partage
# (consentement auto-valide comme au boot), et au demarrage le journal doit mettre en file un rapport
# « crash » complet. L'envoi reseau est coupe (pref de test « envoi_desactive », ecrite en root) : la CI
# n'envoie jamais rien a la prod ; le rapport est lu dans la file de l'appli.
JPREFS="/data/data/$PKG/shared_prefs/fs_crash_journal.xml"
cat > /tmp/fsj.xml <<'XML'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="envoi_desactive" value="true" />
</map>
XML
adb push /tmp/fsj.xml /data/local/tmp/fsj.xml >/dev/null 2>&1 || true
adb shell "cp /data/local/tmp/fsj.xml $JPREFS" >/dev/null 2>&1 || true
U="$(ash stat -c %u "/data/data/$PKG")"
[ -n "$U" ] && adb shell "chown $U:$U $JPREFS; chmod 660 $JPREFS; restorecon $JPREFS" >/dev/null 2>&1 || true

adb logcat -c >/dev/null 2>&1 || true
PID_AVANT="$(ash pidof "$PKG")"
if adb shell am crash "$PKG" >/dev/null 2>&1; then
  notice "Plantage provoque (am crash, pid $PID_AVANT)"
else
  warn "am crash indisponible sur API $API : test du journal de plantage saute"
fi
# Le systeme relance le processus (service d'accessibilite relie) ; on attend la relance du partage puis
# la collecte du journal (20 s apres le demarrage du processus).
RELANCE=0
CAP2=0
i=0
while [ "$i" -lt 45 ]; do
  P="$(ash pidof "$PKG")"
  if [ -n "$P" ] && [ "$P" != "$PID_AVANT" ]; then
    adb logcat -d 2>/dev/null | grep -qF 'relance automatique du partage' && RELANCE=1
    case "$(ash dumpsys media_projection)" in *"$PKG"*) CAP2=1 ;; esac
    adb logcat -d 2>/dev/null | grep -qF 'mis en file' && [ "$CAP2" = 1 ] && break
  fi
  i=$((i + 1)); sleep 2
done
adb logcat -d > "$OUT/client-screen-plantage-logcat-$API.txt" 2>&1 || true
if [ "$RELANCE" = 1 ]; then
  notice "Apres plantage : partage relance automatiquement (mode Ecran client)"
else
  essential_fail "Apres plantage : aucune relance automatique du partage"
fi
if [ "$CAP2" = 1 ]; then
  notice "Apres plantage : capture de nouveau active"
elif [ "$API" -ge 34 ]; then
  warn "Apres plantage : capture non reactivee (meme limite emulateur API $API que le consentement au boot)"
else
  essential_fail "Apres plantage : capture non reactivee"
fi

# Rapport en file : lu en root, verifie (raison, pile, taille, aucun secret).
QDIR="/data/data/$PKG/files/fs-journal/attente"
RAPPORT="$(ash "ls $QDIR" | head -n 1)"
if [ -n "$RAPPORT" ]; then
  adb exec-out cat "$QDIR/$RAPPORT" > "$OUT/client-screen-rapport-$API.json" 2>/dev/null || true
  python3 - "$OUT/client-screen-rapport-$API.json" "$API" <<'PY'
import json, sys
path, api = sys.argv[1], sys.argv[2]
raw = open(path, 'rb').read()
try:
    r = json.loads(raw)
except Exception as e:
    print(f"::error::[API {api}] Rapport de plantage illisible : {e}"); sys.exit(1)
ok = True
def err(m):
    global ok; ok = False; print(f"::error::[API {api}] Rapport de plantage : {m}")
if r.get('raison') not in ('crash', 'jvm'): err(f"raison inattendue {r.get('raison')!r}")
if 'CrashedByAdb' not in r.get('trace', '') and 'Exception' not in r.get('trace', ''): err("pile Java absente")
if len(raw) > 64 * 1024: err(f"rapport trop gros ({len(raw)} octets)")
low = raw.decode('utf-8', 'replace').lower()
for mot in ('password=', 'bearer '):
    if mot in low: err(f"donnee sensible non masquee ({mot})")
if not r.get('logcat'): err("logcat absent")
if r.get('ecran_client') is not True: err("mode Ecran client non signale")
for k in ('version', 'modele', 'android_version', 'horodatage'):
    if not r.get(k): err(f"champ {k} vide")
if ok:
    print(f"::notice::[API {api}] Rapport de plantage complet : raison={r.get('raison')}, {len(raw)} octets, ID={r.get('fs_support_id') or '(inconnu en CI)'}, trace {len(r.get('trace',''))} car., logcat {len(r.get('logcat',''))} car., journal Rust {len(r.get('journal_rust',''))} car.")
sys.exit(0 if ok else 1)
PY
  [ $? = 0 ] || FAIL=1
else
  essential_fail "Aucun rapport de plantage en file apres le redemarrage ($QDIR vide)"
fi

# Non essentiel : ecran « 4K » -> capture plafonnee a 1920 px en mode Ecran client.
ash wm size 3840x2160 >/dev/null 2>&1 || true
sleep 8
CAPW="$(adb logcat -d 2>/dev/null | grep -F 'updateScreenInfo:w:' | tail -n 1 | sed 's/.*updateScreenInfo://; s/[^[:print:]]//g')"
ash wm size reset >/dev/null 2>&1 || true
case "$CAPW" in
  *w:1920,h:1080*|*w:1080,h:1920*) notice "Ecran 3840x2160 : capture plafonnee ($CAPW)" ;;
  "") warn "Ecran 3840x2160 : taille de capture non relevee dans le journal" ;;
  *) warn "Ecran 3840x2160 : taille de capture relevee $CAPW (plafond 1920 attendu)" ;;
esac

# ================= Couleur de l'interface (14/10/2026) : jamais de fenetre en mode Ecran client =================
# Premier lancement de l'interface avec le mode Ecran client actif (preference Kotlin posee plus haut) : la fenetre
# « Choisissez la couleur de FS Support » ne doit PAS s'ouvrir (l'ecran garde Atelier). Controle positif ensuite :
# mode coupe, interface relancee -> la fenetre doit apparaitre (sinon l'absence ne prouve rien : rapporte).
# Les textes Flutter sont lus par uiautomator (arbre d'accessibilite, actif car le service FS Support est lie).
PALETTE_TXT="Choisissez la couleur"
MAIN_ACT="$PKG/com.carriez.flutter_hbb.MainActivity"
ui_dump() {
  adb shell uiautomator dump /sdcard/fs-ui.xml >/dev/null 2>&1 || true
  adb exec-out cat /sdcard/fs-ui.xml 2>/dev/null
}
attendre_ui() {
  # Attend qu'un texte de l'appli apparaisse (au plus ~40 s) ; renvoie le dernier vidage.
  local d="" k=0
  while [ "$k" -lt 20 ]; do
    d="$(ui_dump)"
    case "$d" in *"$PALETTE_TXT"*) break ;; esac
    if [ "$k" -ge 6 ] && printf '%s' "$d" | grep -q "package=\"$PKG\""; then
      # Interface affichee depuis au moins ~12 s (delai de la proposition : 1,2 s apres l'accueil).
      [ "$k" -ge 9 ] && break
    fi
    k=$((k + 1)); sleep 2
  done
  printf '%s' "$d"
}
adb shell am start -n "$MAIN_ACT" >/dev/null 2>&1 || true
D1="$(attendre_ui)"
printf '%s' "$D1" > "$OUT/client-screen-palette-ui-$API.xml"
adb exec-out screencap -p > "$OUT/client-screen-palette-$API.png" 2>/dev/null || true
case "$D1" in
  *"$PALETTE_TXT"*) essential_fail "Mode Ecran client : la fenetre de choix de couleur s'est ouverte (interdit)" ;;
  *"package=\"$PKG\""*) notice "Mode Ecran client : interface ouverte, aucune fenetre de choix de couleur" ;;
  *) warn "Mode Ecran client : interface FS Support non vue par uiautomator (absence de fenetre non prouvee)" ;;
esac
# Controle positif : mode coupe, l'appli relancee doit proposer la couleur.
cat > /tmp/kcs-off.xml <<'XML'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="KEY_START_ON_BOOT_OPT" value="false" />
    <boolean name="KEY_FS_CLIENT_SCREEN" value="false" />
</map>
XML
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb push /tmp/kcs-off.xml /data/local/tmp/kcs-off.xml >/dev/null 2>&1 || true
adb shell "cp /data/local/tmp/kcs-off.xml /data/data/$PKG/shared_prefs/KEY_SHARED_PREFERENCES.xml" >/dev/null 2>&1 || true
U2="$(ash stat -c %u "/data/data/$PKG")"
[ -n "$U2" ] && adb shell "chown $U2:$U2 /data/data/$PKG/shared_prefs/KEY_SHARED_PREFERENCES.xml; chmod 660 /data/data/$PKG/shared_prefs/KEY_SHARED_PREFERENCES.xml; restorecon /data/data/$PKG/shared_prefs/KEY_SHARED_PREFERENCES.xml" >/dev/null 2>&1 || true
adb shell am start -n "$MAIN_ACT" >/dev/null 2>&1 || true
D2="$(attendre_ui)"
printf '%s' "$D2" > "$OUT/palette-hors-ecran-client-ui-$API.xml"
adb exec-out screencap -p > "$OUT/palette-hors-ecran-client-$API.png" 2>/dev/null || true
case "$D2" in
  *"$PALETTE_TXT"*) notice "Controle positif : hors mode Ecran client, la fenetre de choix (Atelier / Ardoise) s'ouvre au premier lancement" ;;
  *) warn "Controle positif : fenetre de choix de couleur non vue hors mode Ecran client (arbre d'accessibilite Flutter absent ?)" ;;
esac

# ---- Artefacts ----
adb logcat -d > "$OUT/client-screen-logcat-$API.txt" 2>&1 || true
ash dumpsys window > "$OUT/client-screen-window-$API.txt" 2>&1 || true

echo "=== Fin e2e Ecran client (API $API) : $( [ "$FAIL" = 0 ] && echo OK || echo ECHEC ) ==="
if [ "$FAIL" = 0 ]; then
  echo "::notice::[API $API] FS Support mode Ecran client : essentiels au vert (mode actif, accessibilite liee, demande de capture au boot ; auto-validation du consentement bloquante et OK sur API<=33, rapportee sur API>=34 — limite emulateur, voir warnings)."
else
  echo "::error::[API $API] FS Support mode Ecran client : au moins une verification essentielle a echoue"
fi
exit "$FAIL"
