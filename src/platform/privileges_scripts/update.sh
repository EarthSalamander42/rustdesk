# FS Support — mise à jour de l'application quand le service est installé.
# Arguments : corps_daemon corps_agent utilisateur pid_courant dossier_source plist_daemon plist_agent
#             étiquette_daemon étiquette_agent bundle_app nom_app [étiquette|chemin anciens …]
set -u
daemon_body=$1 agent_body=$2 user=$3 cur_pid=$4 source_dir=$5 daemon_plist=$6 agent_plist=$7
daemon_label=$8 agent_label=$9 app_bundle=${10} app_name=${11}
shift 11
[ -d "$source_dir" ] || fail "dossier de mise à jour introuvable : $source_dir"
uid=$(id -u "$user" 2>/dev/null || true)

if [ -n "$uid" ]; then
	launchctl bootout gui/"$uid"/"$agent_label" 2>/dev/null || launchctl bootout user/"$uid"/"$agent_label" 2>/dev/null || true
fi
launchctl unload -w "$agent_plist" 2>/dev/null || true
launchctl bootout system/"$daemon_label" 2>/dev/null || launchctl unload -w "$daemon_plist" 2>/dev/null || true
clean_legacy "$uid" "$@"

pids=$(pgrep -x "$app_name" | grep -vx "$cur_pid" || true)
if [ -n "$pids" ]; then echo "$pids" | xargs kill -9 || true; fi

rm -rf "$app_bundle" && ditto "$source_dir" "$app_bundle" || fail "copie de la nouvelle version impossible"
chown -R "$user":staff "$app_bundle" || true
xattr -r -d com.apple.quarantine "$app_bundle" 2>/dev/null || true

write_plist "$daemon_body" "$daemon_plist"
write_plist "$agent_body" "$agent_plist"
load_daemon "$daemon_label" "$daemon_plist"
load_agent "$uid" "$agent_label" "$agent_plist"
