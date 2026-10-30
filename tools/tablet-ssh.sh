#!/bin/bash
# SSH zum Jeazans C107 unter postmarketOS (USB-Netz, Tablet 172.16.42.1).
# Eigener Schluessel ~/.ssh/id_ed25519_tablet und eigene known_hosts-Datei, weil jede
# Neuinstallation (pmbootstrap install) neue Host-Schluessel erzeugt. Nach einer
# Neuinstallation: ssh-keygen -f ~/.ssh/known_hosts_tablet -R 172.16.42.1
# (bzw. -R mit der WLAN-Adresse)
# Aufruf: tablet-ssh.sh [befehl ...]   (ohne Befehl: interaktive Sitzung)
# Ueber WLAN im Heimnetz: TABLET=192.168.x.y tablet-ssh.sh ...  (feste IP seit Kernel r13)
exec ssh -i ~/.ssh/id_ed25519_tablet -o IdentitiesOnly=yes \
	-o UserKnownHostsFile=~/.ssh/known_hosts_tablet -o StrictHostKeyChecking=accept-new \
	-o ConnectTimeout=10 "user@${TABLET:-172.16.42.1}" "$@"
