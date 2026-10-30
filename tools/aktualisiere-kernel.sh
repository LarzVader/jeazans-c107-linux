#!/bin/sh
# Laeuft auf dem Tablet als root (ein sudo fuer alles): installiert die Pakete aus /tmp/pakete/
# (z. B. neuer Kernel und Firmware), legt das von apk/mkinitfs erzeugte Initramfs fuer den PC
# bereit (/tmp/initramfs-neu + .sha256), wartet bis 15 min auf das daraus gebaute Boot-Abbild
# (/tmp/boot-neu.img, die Pruefsummendatei /tmp/boot-neu.sha256 kommt als Signal zuletzt),
# schreibt es mit schreibe-partition.sh nach boot_b (mit Sicherung und Pruefung) und startet neu.
# Kommt kein Abbild, bleibt boot_b unveraendert.
# Aufruf: sudo sh /home/user/werkzeuge/aktualisiere-kernel.sh   (/tmp ist nach jedem Neustart leer,
# darum liegen die Skripte in ~/werkzeuge; nur die Pakete kommen jeweils frisch nach /tmp/pakete)
set -eu
zeit() { echo "$(date +%H:%M:%S) $*"; }

rm -f /tmp/initramfs-neu /tmp/initramfs-neu.sha256 /tmp/boot-neu.img /tmp/boot-neu.sha256
zeit "installiere: $(cd /tmp/pakete && echo *.apk)"
# pmOS setzt /etc/apk/interactive, ohne --no-interactive wartet apk auf ein "y"
apk add --no-interactive /tmp/pakete/*.apk
cp /boot/initramfs /tmp/initramfs-neu
chmod 644 /tmp/initramfs-neu
sha256sum < /tmp/initramfs-neu | cut -d' ' -f1 > /tmp/initramfs-neu.sha256
zeit "Initramfs bereit ($(stat -c%s /tmp/initramfs-neu) Bytes), warte auf das Boot-Abbild vom PC ..."

i=0
while [ ! -s /tmp/boot-neu.sha256 ]; do
	sleep 5
	i=$((i + 5))
	if [ "$i" -ge 900 ]; then zeit "FEHLER: kein Boot-Abbild vom PC, boot_b bleibt unveraendert"; exit 1; fi
done
sh /home/user/werkzeuge/schreibe-partition.sh boot_b /tmp/boot-neu.img "$(cat /tmp/boot-neu.sha256)"
zeit "Neustart"
reboot
