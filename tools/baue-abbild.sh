#!/bin/bash
# Baut das Systemabbild fuer den Jeazans C107 mit pmbootstrap install.
# Fragt einmal nach dem sudo-Passwort und haelt es waehrend des Baus
# wach (pmbootstrap 3.12.1 schaltet seinen eigenen sudo-Timer nie ein).
# Zwischendurch fragt pmbootstrap nach dem Passwort fuer den Benutzer
# "user" auf dem Tablet.
# Ergebnis: Status und Dauer neben dem Skript in abbild-build.status,
# Abbild in ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/,
# volles Protokoll in ~/.local/var/pmbootstrap/log.txt
# Optionen werden an pmbootstrap install durchgereicht, fuer Netboot z. B.:
#   baue-abbild.sh --no-split --add postmarketos-mkinitfs-hook-netboot
set -u
status_datei="$(cd "$(dirname "$0")" && pwd)"/abbild-build.status
rm -f "$status_datei"
status="abgebrochen"
wachhalter=""
start=$(date +%s)

beenden() {
	[ -n "$wachhalter" ] && kill "$wachhalter" 2>/dev/null
	dauer=$(( ($(date +%s) - start) / 60 ))
	echo "$status $dauer" > "$status_datei"
	echo "Abbild-Bau beendet: Status $status nach $dauer Minuten"
}
trap beenden EXIT

if ! sudo -v; then
	status="kein-sudo"
	exit 1
fi
( while sleep 60; do sudo -nv || exit; done ) &
wachhalter=$!

pmbootstrap install "$@"
status=$?
exit "$status"
