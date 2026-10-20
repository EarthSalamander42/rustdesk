# FS Support — désinstallation du service macOS (nouveaux et anciens noms).
# Arguments : utilisateur étiquette|chemin [étiquette|chemin …]
set -u
user=$1
shift
uid=$(id -u "$user" 2>/dev/null || true)
clean_legacy "$uid" "$@"
echo "FS-OK: service retiré"
