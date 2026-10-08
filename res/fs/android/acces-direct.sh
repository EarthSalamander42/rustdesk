#!/system/bin/sh
# FS Support — Acces direct (prise en main sans personne devant l'ecran)
#
# A executer SUR l'appareil Android, une seule fois par appareil :
#   adb push acces-direct.sh /data/local/tmp/acces-direct.sh
#   adb shell sh /data/local/tmp/acces-direct.sh
#
# Shell POSIX (toybox / mksh), PAS de bash : pas de tableaux, pas de « local »,
# pas de « [[ ]] ». Le script ne s'arrete jamais au premier echec : il tente tout,
# puis affiche un recapitulatif en francais de ce qui a marche et de ce qui a echoue.
#
# Ce que fait le script (compte shell, sans root) :
#   - capture d'ecran sans fenetre de consentement (appops PROJECT_MEDIA) ;
#   - fenetre par-dessus l'ecran (appops SYSTEM_ALERT_WINDOW) ;
#   - WRITE_SECURE_SETTINGS (permet a l'app de reactiver seule son accessibilite) ;
#   - service d'accessibilite FS Support ajoute (sans ecraser les autres) ;
#   - sortie de l'optimisation de batterie (deviceidle whitelist) ;
#   - notifications (Android 13+).

PKG="fr.fssolutions.support"
SERVICE="$PKG/com.carriez.flutter_hbb.InputService"

ANDROID_RELEASE="$(getprop ro.build.version.release 2>/dev/null)"
ANDROID_SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
[ -z "$ANDROID_SDK" ] && ANDROID_SDK=0

# Recapitulatif : on accumule des lignes « OK/ECHEC : ... » dans $SUMMARY.
SUMMARY=""
OK_COUNT=0
FAIL_COUNT=0

note_ok() {
    OK_COUNT=$((OK_COUNT + 1))
    SUMMARY="$SUMMARY
  [ OK   ] $1"
}

note_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    SUMMARY="$SUMMARY
  [ ECHEC] $1"
}

# run_step "libelle" commande...  -> execute, journalise, ne stoppe jamais.
run_step() {
    label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        note_ok "$label"
        return 0
    fi
    note_fail "$label"
    return 1
}

echo "=== FS Support : preparation de l'acces direct ==="
echo "Appareil : Android ${ANDROID_RELEASE:-inconnu} (API ${ANDROID_SDK})"
echo "Paquet   : $PKG"
echo

# L'application doit etre installee.
if ! pm path "$PKG" >/dev/null 2>&1; then
    echo "ERREUR : l'application $PKG n'est pas installee."
    echo "Installez d'abord l'APK FS Support (adb install -r ...) puis relancez ce script."
    exit 1
fi

# 1. Capture d'ecran sans fenetre de consentement.
run_step "Capture d'ecran sans fenetre (PROJECT_MEDIA)" \
    appops set "$PKG" PROJECT_MEDIA allow

# 2. Fenetre par-dessus l'ecran.
run_step "Fenetre par-dessus l'ecran (SYSTEM_ALERT_WINDOW)" \
    appops set "$PKG" SYSTEM_ALERT_WINDOW allow

# 3. WRITE_SECURE_SETTINGS : permet a l'app de reactiver seule son accessibilite.
#    C'est une permission de « developpement » : pm grant marche si elle est declaree
#    au manifeste (elle l'est dans FS Support).
run_step "Reglages securises (WRITE_SECURE_SETTINGS)" \
    pm grant "$PKG" android.permission.WRITE_SECURE_SETTINGS

# 4. Service d'accessibilite : on AJOUTE le notre sans ecraser ceux deja presents.
CURRENT="$(settings get secure enabled_accessibility_services 2>/dev/null)"
if [ "$CURRENT" = "null" ]; then
    CURRENT=""
fi
FOUND=0
if [ -n "$CURRENT" ]; then
    OLDIFS="$IFS"
    IFS=":"
    for existing in $CURRENT; do
        if [ "$existing" = "$SERVICE" ]; then
            FOUND=1
        fi
    done
    IFS="$OLDIFS"
fi
if [ "$FOUND" = "1" ]; then
    NEWLIST="$CURRENT"
elif [ -z "$CURRENT" ]; then
    NEWLIST="$SERVICE"
else
    NEWLIST="$CURRENT:$SERVICE"
fi

ACC_OK=1
if ! settings put secure enabled_accessibility_services "$NEWLIST" >/dev/null 2>&1; then
    ACC_OK=0
fi
if ! settings put secure accessibility_enabled 1 >/dev/null 2>&1; then
    ACC_OK=0
fi
# Verification : notre service est bien dans la liste effective.
VERIFY="$(settings get secure enabled_accessibility_services 2>/dev/null)"
case ":$VERIFY:" in
    *":$SERVICE:"*) ;;
    *) ACC_OK=0 ;;
esac
if [ "$ACC_OK" = "1" ]; then
    note_ok "Service d'accessibilite FS Support active"
else
    note_fail "Service d'accessibilite FS Support active (verifier dans Reglages > Accessibilite)"
fi

# 5. Sortie de l'optimisation de batterie (service en tache de fond fiable).
run_step "Optimisation de batterie ignoree (deviceidle)" \
    dumpsys deviceidle whitelist +"$PKG"

# 6. Notifications (Android 13+). Ailleurs la permission n'existe pas : echec ignore.
if [ "$ANDROID_SDK" -ge 33 ] 2>/dev/null; then
    run_step "Notifications autorisees (POST_NOTIFICATIONS)" \
        pm grant "$PKG" android.permission.POST_NOTIFICATIONS
else
    note_ok "Notifications : non requises avant Android 13 (ignore)"
fi

echo
echo "=== Recapitulatif ==="
printf '%s\n' "$SUMMARY"
echo
echo "Reussis : $OK_COUNT    Echecs : $FAIL_COUNT"
echo
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "Acces direct pret. Ouvrez FS Support une fois, activez « Acces direct » sur"
    echo "l'ecran de partage, puis cet appareil sera joignable sans intervention sur place."
    exit 0
fi
echo "Certaines etapes ont echoue (voir ci-dessus)."
echo "Sur Android 14+ (API 34+), la capture sans fenetre peut rester limitee : une"
echo "fenetre de consentement a chaque demarrage est alors imposee par le systeme."
exit 2
