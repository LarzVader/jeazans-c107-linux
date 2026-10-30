#!/bin/sh
# Laeuft auf dem Tablet als root (ein sudo fuer alles): testet den Uebernahme-Treiber sun55i_takeover
# in Stufen, jede wartet auf Enter im Terminal. Stufe 1 aendert nichts am Bild. Ab Stufe 2 ist der
# Notaus scharf: Ein/Aus oder Leiser schalten sofort ab, nach 15 min ohne Lauter ebenso. Prueft die
# Konsole, kmscube und die Helligkeit, den Desktop prueft anzeige-beim-start.sh. Am Ende ein Neustart.
# Mitschrift fuer den PC: /tmp/anzeige-test.log
# Aufruf: sudo sh /home/user/werkzeuge/anzeige-test.sh
set -u
W=/home/user/werkzeuge
LOG=/tmp/anzeige-test.log
LICHT=/sys/class/backlight/panel/brightness
: > "$LOG"
chmod 644 "$LOG"

sag() { echo "$*" | tee -a "$LOG"; }
weiter() {
	printf '\n>>> %s\n    Enter druecken ... ' "$1"
	read -r _
	echo "$(date +%H:%M:%S) weiter: $1" >> "$LOG"
}
# Kernelmeldungen seit dem letzten Aufruf
gesehen=$(dmesg | wc -l)
neues() {
	dmesg | tail -n +"$((gesehen + 1))" | tee -a "$LOG"
	gesehen=$(dmesg | wc -l)
}
bild_irqs() {
	awk '/51c1000/ { s = 0; for (i = 2; i <= NF && $i ~ /^[0-9]+$/; i++) s += $i; print s }' /proc/interrupts
}
konsole() {
	printf '\033[2J\033[H\n\n   %s\n' "$1" > /dev/tty1
}
karte() {
	for c in /sys/class/drm/card?; do
		if [ "$(basename "$(readlink "$c/device/driver")")" = sun55i-takeover ]; then
			echo "/dev/dri/$(basename "$c")"
		fi
	done
}
zustand() {
	for d in /sys/kernel/debug/dri/*; do
		if grep -q sun4i-drm "$d/name" 2>/dev/null; then
			grep -E 'fb=|active=|size=|pitch|format=' "$d/state" | tee -a "$LOG"
		fi
	done
}

if grep -q '^sun55i_takeover ' /proc/modules; then
	echo "Der Treiber ist schon geladen. Dieser Test braucht einen Start ohne ihn, geht also nur mit"
	echo "Kernel-Lockdown aus und ohne /usr/lib/modules-load.d/jeazans-c107-anzeige.conf."
	exit 1
fi
sag "=== $(date +%H:%M:%S) Vorbereitung, Kernel $(uname -r) ==="
find "/lib/modules/$(uname -r)" -name 'sun55i_takeover*' | tee -a "$LOG"
command -v kmscube > /dev/null || apk add --no-interactive kmscube 2>&1 | tail -n 1 | tee -a "$LOG"

sag "=== $(date +%H:%M:%S) Stufe 1: nur pruefen, das Bild bleibt, wie es ist ==="
modprobe sun55i_takeover check_only=1
neues
rmmod sun55i_takeover
if ! grep -q "frame interrupts, one every" "$LOG"; then
	sag "FEHLER: Der Bild-Interrupt kommt nicht an. Es wurde nichts veraendert, der Desktop laeuft weiter."
	exit 1
fi
sag "Stufe 1 in Ordnung."

weiter "Stufe 2: Der Desktop wird beendet, der Treiber uebernimmt das Bild, der Notaus wird scharf."
systemd-run --quiet --collect --unit=anzeige-notaus python3 "$W/display-notaus.py" --sekunden 900
sleep 1
if ! systemctl is-active -q anzeige-notaus.service; then
	sag "FEHLER: Der Notaus startet nicht, Abbruch. Der Desktop laeuft weiter."
	exit 1
fi
sag "=== $(date +%H:%M:%S) Stufe 2 ==="
systemctl stop plasma-mobile.service
sleep 2
chvt 1
modprobe sun55i_takeover
sleep 2
neues
konsole "TREIBER LAEUFT. Diese Schrift liegt im neuen Bildspeicher. Weiter am PC."
sleep 1
zustand
sag "Karte: $(karte)"

weiter "Siehst du am Tablet die Schrift TREIBER LAEUFT? Dann weiter zu Stufe 3: 10 s drehender Wuerfel von der GPU."
sag "=== $(date +%H:%M:%S) Stufe 3 ==="
vor=$(bild_irqs)
timeout 30 kmscube -D "$(karte)" -c 600 2>&1 | grep -E "GL_RENDERER|GL_VERSION|Rendered|ailed|rror" | tee -a "$LOG"
sag "Bild-Interrupts dabei: $(($(bild_irqs) - vor))"
neues
konsole "Wuerfel fertig. Weiter am PC."

weiter "Stufe 4: Helligkeit 5, 50, 100 Prozent, dann Licht aus, dann wieder 20 Prozent, je 3 s."
sag "=== $(date +%H:%M:%S) Stufe 4 ==="
for wert in 5 50 100 0 20; do
	konsole "Helligkeit $wert Prozent"
	echo "$wert" > "$LICHT"
	sag "Helligkeit $wert: $(cat "$LICHT")"
	sleep 3
done
konsole "Helligkeit fertig. Weiter am PC."

# Einen Desktop-Test gibt es hier nicht: KWin laeuft als Nutzerdienst weiter und hat seine logind-
# Sitzung verloren, plasma-mobile.service startet ihn nicht neu. Dafuer anzeige-beim-start.sh.
printf '\nDer Desktop kommt erst nach dem Neustart wieder, dann mit simpledrm.\n'
antwort=""
while [ "$antwort" != neustart ]; do
	printf '>>> Zum Neustart das Wort neustart eintippen und Enter druecken: '
	read -r antwort
done
neues
sync
reboot
