#!/bin/bash
# Baut den Kernel linux-jeazans-c107 mit pmbootstrap.
# Fragt einmal nach dem sudo-Passwort und haelt es waehrend des langen Builds
# wach (pmbootstrap 3.12.1 schaltet seinen eigenen sudo-Timer nie ein).
# Weitere Paketnamen als Argumente baut es danach im selben Lauf mit,
# z. B. baue-kernel.sh device-jeazans-c107
# Ergebnis: Status und Dauer neben dem Skript in kernel-build.status,
# volles Protokoll in ~/.local/var/pmbootstrap/log.txt
set -u
status_datei="$(cd "$(dirname "$0")" && pwd)"/kernel-build.status
rm -f "$status_datei"
status="abgebrochen"
wachhalter=""
start=$(date +%s)

beenden() {
	[ -n "$wachhalter" ] && kill "$wachhalter" 2>/dev/null
	dauer=$(( ($(date +%s) - start) / 60 ))
	echo "$status $dauer" > "$status_datei"
	echo "Kernel-Build beendet: Status $status nach $dauer Minuten"
}
trap beenden EXIT

if ! sudo -v; then
	status="kein-sudo"
	exit 1
fi
( while sleep 60; do sudo -nv || exit; done ) &
wachhalter=$!

pmbootstrap build linux-jeazans-c107
status=$?

# Weitere Pakete im selben Lauf, solange sudo noch wach ist
if [ "$status" -eq 0 ] && [ $# -gt 0 ]; then
	pmbootstrap build "$@"
	status=$?
fi
exit "$status"
