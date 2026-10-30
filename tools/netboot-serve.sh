#!/bin/bash
# Startet "pmbootstrap netboot serve" fuer den Jeazans C107 (Root-Dateisystem per NBD ueber USB).
# Fragt einmal nach dem sudo-Passwort und haelt es wach, damit nbd-server auch nach einem
# Neustart des Tablets ohne neue Passwortabfrage wieder anspringt.
# pmbootstrap wartet, bis der PC per DHCP vom Tablet 172.16.42.2 bekommt, und bedient dann
# 172.16.42.2:9999 mit ~/.local/var/pmbootstrap/images_netboot/jeazans-c107.img.
# Beenden mit Strg+C.
set -u
wachhalter=""
beenden() {
	[ -n "$wachhalter" ] && kill "$wachhalter" 2>/dev/null
}
trap beenden EXIT

sudo -v || exit 1
( while sleep 60; do sudo -nv || exit; done ) &
wachhalter=$!

pmbootstrap netboot serve "$@"
