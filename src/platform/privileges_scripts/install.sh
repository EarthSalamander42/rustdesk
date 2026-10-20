# FS Support — installation du service macOS (LaunchDaemon + LaunchAgent).
# Arguments : corps_daemon corps_agent utilisateur plist_daemon plist_agent étiquette_daemon
#             étiquette_agent conf1 conf2 dossier_conf_root [ancienne_étiquette|ancien_chemin …]
set -u
daemon_body=$1 agent_body=$2 user=$3 daemon_plist=$4 agent_plist=$5
daemon_label=$6 agent_label=$7 conf1=$8 conf2=$9 root_conf=${10}
shift 10
uid=$(id -u "$user" 2>/dev/null || true)

clean_legacy "$uid" "$@"
write_plist "$daemon_body" "$daemon_plist"
write_plist "$agent_body" "$agent_plist"

# Configuration de l'utilisateur recopiée pour le service root (comme RustDesk) : non bloquant.
if [ -n "$root_conf" ]; then
	mkdir -p "$root_conf" 2>/dev/null || true
	for f in "$conf1" "$conf2"; do
		[ -f "$f" ] && cp -f "$f" "$root_conf/" 2>/dev/null || true
	done
fi

load_daemon "$daemon_label" "$daemon_plist"
load_agent "$uid" "$agent_label" "$agent_plist"
echo "FS-OK: service $daemon_label et agent $agent_label installés"
