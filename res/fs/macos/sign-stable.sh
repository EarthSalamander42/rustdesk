#!/usr/bin/env bash
# FS Support — signature macOS avec un certificat AUTO-SIGNÉ et CONSTANT (CI GitHub, runner macOS uniquement).
#
# Pourquoi : signée « ad hoc » (codesign --sign -), chaque version a une identité différente pour macOS ; les
# autorisations données à la main (Accessibilité, Enregistrement de l'écran) ne suivent pas la mise à jour et
# doivent être recochées. Signée avec toujours le même certificat, l'« exigence désignée » de l'app
# (identifiant + empreinte du certificat) reste la même : macOS reconnaît l'app d'une version à l'autre.
# Ce n'est PAS une signature Apple (pas de notarisation) : la quarantaine du premier téléchargement reste.
#
# Entrées (secrets GitHub du fork, jamais affichés) :
#   FS_MACOS_SIGN_P12       certificat + clé, fichier .p12 encodé en base64
#   FS_MACOS_SIGN_PASSWORD  mot de passe du .p12
# Usage : bash res/fs/macos/sign-stable.sh "<chemin>/FS Support.app"
# Préparation du certificat : res/fs/macos/generer-certificat-signature.sh (à lancer une seule fois par Jason).
set -euo pipefail

APP="${1:?chemin de l’app manquant}"
: "${FS_MACOS_SIGN_P12:?secret FS_MACOS_SIGN_P12 absent}"
: "${FS_MACOS_SIGN_PASSWORD:?secret FS_MACOS_SIGN_PASSWORD absent}"

TMP="${RUNNER_TEMP:-$(mktemp -d)}"
KC="$TMP/fs-signature.keychain-db"
P12="$TMP/fs-signature.p12"
KCPW="$(openssl rand -hex 24)"

nettoyer() {
  rm -f "$P12"
  security delete-keychain "$KC" >/dev/null 2>&1 || true
}
trap nettoyer EXIT

# Trousseau temporaire, propre à ce job.
security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KCPW" "$KC"
printf '%s' "$FS_MACOS_SIGN_P12" | base64 --decode > "$P12"
security import "$P12" -k "$KC" -P "$FS_MACOS_SIGN_PASSWORD" -T /usr/bin/codesign >/dev/null
rm -f "$P12"
# codesign doit pouvoir lire la clé sans fenêtre d'autorisation.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null
# Trousseau ajouté à la liste de recherche (en tête), sans retirer ceux du runner.
EXISTANTS="$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KC" $EXISTANTS

# Identité : un certificat auto-signé n'est pas « approuvé » (CSSMERR_TP_NOT_TRUSTED), codesign l'utilise
# quand même ; on la vise par son empreinte SHA-1 (sans -v, qui ne liste que les identités approuvées).
HASH="$(security find-identity -p codesigning "$KC" | awk '/^ *[0-9]+\)/ {print $2; exit}')"
if [ -z "$HASH" ]; then
  echo "::error title=Signature macOS::aucune identité de signature de code dans FS_MACOS_SIGN_P12"
  exit 1
fi
NOM="$(security find-identity -p codesigning "$KC" | awk -F'"' '/^ *[0-9]+\)/ {print $2; exit}')"

# Même portée que la signature ad hoc d'avant (--deep), avec l'identité constante.
codesign --force --deep --keychain "$KC" --sign "$HASH" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# Exigence désignée : c'est elle que macOS compare d'une version à l'autre (autorisations conservées).
EXIG="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p' | head -n 1)"
echo "::notice title=Signature macOS::certificat constant « ${NOM} » (empreinte ${HASH:0:8}…) ; exigence désignée : ${EXIG}"
