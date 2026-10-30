#!/bin/sh
# Laeuft auf dem Tablet als root: liest 20 s lang die Rohdaten des Touch-Controllers neben dem
# Treiber mit (Register 0x80: Anzahl der Finger, 3 Bytes, dann je Punkt Y lo, Y hi|Flags,
# X lo, X hi|ID) und zeichnet zugleich die Ereignisse des Treibers auf.
# Ergebnis: /tmp/touch-roh.txt (Uptime + 8 Bytes je Zeile) und /tmp/touch-ev.txt (evtest).
# Aufruf: sudo sh /home/user/werkzeuge/beruehrung-rohdaten.sh
set -eu
geraet=""
for d in /sys/class/input/event*; do
	if grep -q "silead" "$d/device/name" 2>/dev/null; then
		geraet=/dev/input/$(basename "$d")
		client=$(basename "$(readlink -f "$d/device/device")")
	fi
done
if [ -z "$geraet" ]; then echo "FEHLER: kein Silead-Eingabegeraet"; exit 1; fi
bus=${client%%-*}
modprobe i2c-dev
command -v i2ctransfer >/dev/null || apk add --no-interactive i2c-tools >/dev/null
command -v evtest >/dev/null || apk add --no-interactive evtest >/dev/null

echo "Bus $bus, $geraet. Jetzt jeweils still halten:"
echo "6 s Bildschirmmitte, dann 6 s Mitte des linken Rands, dann 6 s Ecke unten rechts."
# SIGTERM statt SIGINT: im Hintergrund einer Shell ohne Terminal ist SIGINT ignoriert
timeout 20 evtest "$geraet" > /tmp/touch-ev.txt 2>&1 &
ende=$(( $(cut -d. -f1 /proc/uptime) + 20 ))
: > /tmp/touch-roh.txt
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$ende" ]; do
	echo "$(cut -d' ' -f1 /proc/uptime) $(i2ctransfer -f -y "$bus" w1@0x40 0x80 r8)" >> /tmp/touch-roh.txt
done
wait
chmod 644 /tmp/touch-roh.txt /tmp/touch-ev.txt
echo "fertig: $(wc -l < /tmp/touch-roh.txt) Rohdaten-Zeilen"
