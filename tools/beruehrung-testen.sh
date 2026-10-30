#!/bin/sh
# Laeuft auf dem Tablet als root: zeichnet 25 s lang die Beruehrungen des Touchscreens (Silead)
# mit evtest auf, nach /tmp/touch-test.txt (lesbar fuer alle, Auswertung vom PC aus).
# Aufruf: sudo sh /home/user/werkzeuge/beruehrung-testen.sh
set -eu
geraet=""
for d in /sys/class/input/event*; do
	if grep -q "silead" "$d/device/name" 2>/dev/null; then
		geraet=/dev/input/$(basename "$d")
	fi
done
if [ -z "$geraet" ]; then echo "FEHLER: kein Silead-Eingabegeraet"; exit 1; fi
command -v evtest >/dev/null || apk add --no-interactive evtest >/dev/null
echo "Geraet $geraet. Jetzt 25 s lang nacheinander die vier Ecken antippen (Tablet quer):"
echo "oben links, oben rechts, unten rechts, unten links."
timeout -s INT 25 evtest "$geraet" > /tmp/touch-test.txt 2>&1 || true
chmod 644 /tmp/touch-test.txt
echo "fertig: $(grep -c ABS_MT_POSITION_X /tmp/touch-test.txt) X-Meldungen aufgezeichnet"
