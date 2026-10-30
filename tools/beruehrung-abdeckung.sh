#!/bin/sh
# Laeuft auf dem Tablet als root: zeichnet die Ereignisse des Touch-Treibers auf, waehrend der
# Finger ueber die ganze Flaeche streicht. Die Karte daraus erzeugt am PC pmos/werkzeuge/touch-karte.py.
# Ergebnis: /tmp/touch-ev.txt
# Aufruf: sudo sh /home/user/werkzeuge/beruehrung-abdeckung.sh [sekunden]
set -eu
n=${1:-45}
geraet=""
for d in /sys/class/input/event*; do
	if grep -q "silead" "$d/device/name" 2>/dev/null; then
		geraet=/dev/input/$(basename "$d")
	fi
done
if [ -z "$geraet" ]; then echo "FEHLER: kein Silead-Eingabegeraet"; exit 1; fi
echo "JETZT $n Sekunden lang langsam ueber den ganzen Bildschirm streichen, auch ganz am Rand und"
echo "in allen vier Ecken, besonders unten links ..."
# SIGTERM statt SIGINT: im Hintergrund einer Shell ohne Terminal ist SIGINT ignoriert
timeout -s TERM "$n" evtest "$geraet" > /tmp/touch-ev.txt 2>&1 || true
chmod 644 /tmp/touch-ev.txt
echo "Fertig: $(grep -c ABS_MT_POSITION /tmp/touch-ev.txt) Positionswerte."
