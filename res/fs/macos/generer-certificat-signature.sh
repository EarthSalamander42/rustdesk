#!/usr/bin/env bash
# FS Support — certificat de signature de code macOS AUTO-SIGNÉ et CONSTANT (à lancer UNE fois, par Jason).
#
# Sert à la CI du fork (res/fs/macos/sign-stable.sh) : signée toujours avec ce même certificat, l'app garde la même
# identité pour macOS d'une version à l'autre, et les autorisations (Accessibilité, Enregistrement de l'écran)
# ne sont plus à recocher après chaque mise à jour. Pas une signature Apple : la quarantaine du 1er téléchargement reste.
#
# Fonctionne dans Git Bash (Windows) ou le Terminal (macOS) : il ne faut qu'openssl. Rien n'est affiché à l'écran :
# la clé, le .p12 et le mot de passe sont écrits dans un dossier privé.
#
#   bash generer-certificat-signature.sh                 # crée le dossier et les fichiers (refuse s'ils existent)
#   bash generer-certificat-signature.sh copier-p12      # copie le secret FS_MACOS_SIGN_P12 dans le presse-papiers
#   bash generer-certificat-signature.sh copier-mdp      # copie le secret FS_MACOS_SIGN_PASSWORD dans le presse-papiers
#
# Ensuite (3 étapes) :
#   1. GitHub › EarthSalamander42/rustdesk › Settings › Secrets and variables › Actions › « New repository secret ».
#   2. Nom FS_MACOS_SIGN_P12 : coller (copier-p12) ; puis nom FS_MACOS_SIGN_PASSWORD : coller (copier-mdp).
#   3. Garder le dossier (gestionnaire de mots de passe ou support chiffré) : perdu, les autorisations Mac seront à
#      recocher une dernière fois avec un nouveau certificat. Ne jamais le mettre dans un dépôt.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash : ne pas transformer « /CN=… » en chemin Windows.
umask 077

DIR="${FS_SIGNATURE_DIR:-$HOME/fs-support-signature-mac}"
# Git Bash : chemins « C:/… » (openssl Windows ne lit pas « /c/… » quand la conversion MSYS est coupée).
if command -v cygpath >/dev/null 2>&1; then DIR="$(cygpath -m "$DIR")"; fi
P12="$DIR/fs-support-signature.p12"
B64="$DIR/FS_MACOS_SIGN_P12.txt"
MDP="$DIR/FS_MACOS_SIGN_PASSWORD.txt"
CN="FS Solutions - FS Support"

copier() {
  local f="$1"
  [ -s "$f" ] || { echo "Fichier absent : $f (lancer d'abord le script sans argument)." >&2; exit 1; }
  if command -v clip.exe >/dev/null 2>&1; then tr -d '\n' < "$f" | clip.exe
  elif command -v pbcopy >/dev/null 2>&1; then tr -d '\n' < "$f" | pbcopy
  else echo "Pas de presse-papiers trouvé : ouvrir $f à la main." >&2; exit 1; fi
  echo "Copié dans le presse-papiers ($(basename "$f" .txt)). Collez-le dans le secret GitHub du même nom."
}

case "${1:-}" in
  copier-p12) copier "$B64"; exit 0 ;;
  copier-mdp) copier "$MDP"; exit 0 ;;
  "") ;;
  *) echo "Usage : $0 [copier-p12|copier-mdp]" >&2; exit 2 ;;
esac

command -v openssl >/dev/null 2>&1 || { echo "openssl introuvable." >&2; exit 1; }
if [ -e "$P12" ]; then
  echo "Un certificat existe déjà dans $DIR : rien n'est remplacé (le changer ferait perdre les autorisations Mac)." >&2
  exit 1
fi
mkdir -p "$DIR"
chmod 700 "$DIR" 2>/dev/null || true

# Certificat de signature de code, 20 ans, RSA 3072.
openssl req -x509 -newkey rsa:3072 -sha256 -days 7300 -nodes \
  -keyout "$DIR/cle-privee.pem" -out "$DIR/certificat.pem" \
  -subj "/CN=$CN/O=FS Solutions/C=FR" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# Mot de passe aléatoire du .p12 (jamais affiché).
openssl rand -base64 33 | tr -d '/+=\n' | cut -c1-32 > "$MDP"

# .p12 lisible par le trousseau macOS (« security import » refuse le chiffrement par défaut d'OpenSSL 3).
openssl pkcs12 -export -inkey "$DIR/cle-privee.pem" -in "$DIR/certificat.pem" -name "$CN" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -out "$P12" -passout "file:$MDP"

# Secret GitHub = .p12 en base64 sur une ligne.
openssl base64 -A -in "$P12" > "$B64"

EMPREINTE="$(openssl x509 -in "$DIR/certificat.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
echo "Certificat « $CN » créé dans : $DIR"
echo "Empreinte SHA-1 (publique) : $EMPREINTE"
echo "Suite : bash $0 copier-p12  puis  bash $0 copier-mdp  (voir les 3 étapes en tête du script)."
