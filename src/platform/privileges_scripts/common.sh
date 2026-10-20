# FS Support — fonctions communes aux scripts du service macOS (exécutés en root via osascript).
# Tous les chemins et étiquettes arrivent en arguments et restent entre guillemets : le nom de
# l'application contient une espace (« FS Support »).
fail() { echo "FS-ERREUR: $*" >&2; exit 1; }

# Arrête et retire d'anciennes définitions (« étiquette|chemin »), y compris dans la session de l'utilisateur.
clean_legacy() {
	local uid=$1 entry label plist
	shift
	for entry in "$@"; do
		label=${entry%%|*}
		plist=${entry#*|}
		[ -n "$label" ] || continue
		launchctl bootout system/"$label" 2>/dev/null || true
		if [ -n "$uid" ]; then
			launchctl bootout gui/"$uid"/"$label" 2>/dev/null || launchctl bootout user/"$uid"/"$label" 2>/dev/null || true
		fi
		if [ -n "$plist" ] && [ -f "$plist" ]; then
			launchctl unload -w "$plist" 2>/dev/null || true
			rm -f "$plist" || fail "impossible de supprimer l'ancien fichier $plist"
		fi
	done
}

# Écrit une définition launchd de façon atomique, vérifiée par plutil, root:wheel 644.
write_plist() {
	local body=$1 dest=$2 tmp
	tmp="$dest.tmp.$$"
	printf '%s\n' "$body" >"$tmp" || { rm -f "$tmp"; fail "écriture de $dest impossible"; }
	chown root:wheel "$tmp" && chmod 644 "$tmp" || { rm -f "$tmp"; fail "droits de $dest impossibles"; }
	plutil -lint -s "$tmp" >/dev/null || { rm -f "$tmp"; fail "définition $dest invalide"; }
	mv -f "$tmp" "$dest" || { rm -f "$tmp"; fail "installation de $dest impossible"; }
}

load_daemon() {
	local label=$1 plist=$2
	launchctl bootout system/"$label" 2>/dev/null || true
	launchctl bootstrap system "$plist" 2>/dev/null || launchctl load -w "$plist" ||
		fail "launchctl refuse de charger le service système $label"
	launchctl print system/"$label" >/dev/null 2>&1 || fail "le service système $label n'est pas chargé"
}

load_agent() {
	local uid=$1 label=$2 plist=$3
	if [ -n "$uid" ]; then
		launchctl bootout gui/"$uid"/"$label" 2>/dev/null || true
		launchctl bootstrap gui/"$uid" "$plist" 2>/dev/null ||
			launchctl bootstrap user/"$uid" "$plist" 2>/dev/null ||
			launchctl asuser "$uid" launchctl load -w "$plist" 2>/dev/null || true
		launchctl kickstart gui/"$uid"/"$label" 2>/dev/null || launchctl kickstart user/"$uid"/"$label" 2>/dev/null || true
	else
		launchctl load -w -S LoginWindow "$plist" 2>/dev/null || true
	fi
}
