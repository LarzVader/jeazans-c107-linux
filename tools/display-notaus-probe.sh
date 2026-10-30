#!/bin/sh
# Laeuft auf dem Tablet als root: probt den Notaus am laufenden Panel (simpledrm, der U-Boot hat es
# eingeschaltet). Nach der Schienen-Probe bleibt das Bild weg, bis der U-Boot das Panel neu
# einrichtet, darum am Ende ein Neustart.
# Aufruf: sudo sh /home/user/werkzeuge/display-notaus-probe.sh
set -u
NOTAUS="python3 /home/user/werkzeuge/display-notaus.py"
licht() { echo "$1" > /sys/class/backlight/panel/brightness; }

sync
echo
echo "=== 1/3: Schiene. Das Hintergrundlicht bleibt an. DRUECK JETZT LEISER. ==="
$NOTAUS --sekunden 60 --nur-schiene
echo "Das Bild sollte jetzt weg sein oder sich deutlich veraendert haben. 10 s zum Ansehen ..."
sleep 10
# Nicht laenger stromlos als noetig, solange der DSI noch laeuft. Die weiteren Proben nur mit Licht.
$NOTAUS --schiene-an

echo
echo "=== 2/3: Totmann. Licht ist an. Einmal LAUTER druecken, dann nichts mehr tun. ==="
echo "    Das Licht geht rund 20 s nach dem Druck von selbst aus."
licht 20
$NOTAUS --sekunden 20 --nur-licht
sleep 5

echo
echo "=== 3/3: Ein/Aus-Taste. Licht ist an. DRUECK JETZT KURZ EIN/AUS. ==="
licht 20
$NOTAUS --sekunden 60 --nur-licht
sleep 5

echo
echo "=== Probe fertig, Neustart. Danach muss das Bild normal wiederkommen. ==="
sync
sleep 2
reboot
