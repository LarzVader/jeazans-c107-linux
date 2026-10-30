#!/bin/bash
# Schleifentest fuer den USB-UART-Adapter (CP2102), noch ohne Tablet:
# TXD und RXD am Adapter mit einem Jumperkabel verbinden, dann dieses Skript starten.
# Es sendet einen Text und prueft, ob er unveraendert zurueckkommt.
set -u
port="${1:-/dev/ttyUSB0}"

if [ ! -e "$port" ]; then
    echo "Kein $port gefunden. Steckt der Adapter? (lsusb muss 10c4:ea60 zeigen)"
    exit 1
fi
if [ ! -r "$port" ] || [ ! -w "$port" ]; then
    echo "Keine Rechte an $port. udev-Regel 52-tablet-linux.rules installiert und Adapter danach neu eingesteckt?"
    exit 1
fi

stty -F "$port" 115200 raw -echo cs8 -cstopb -parenb -crtscts clocal
probe="Schleifentest-$RANDOM"

exec 3<>"$port"
timeout 0.3 cat <&3 >/dev/null    # alte Reste im Puffer verwerfen
printf '%s\n' "$probe" >&3
antwort=$(timeout 1 head -n1 <&3)
exec 3>&-

if [ "$antwort" = "$probe" ]; then
    echo "OK: Der Adapter sendet und empfaengt sauber."
elif [ -z "$antwort" ]; then
    echo "Nichts zurueckgekommen. Steckt das Kabel wirklich zwischen TXD und RXD?"
    exit 2
else
    echo "Falsche Antwort: '$antwort' statt '$probe'. Kabel wackelt oder Adapter defekt."
    exit 3
fi
