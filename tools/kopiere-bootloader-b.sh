#!/bin/sh
# Laeuft auf dem Tablet als root: kopiert die Boot-Ressourcen (FAT mit Logos, Schriften und
# lcd_compatible) von bootloader_a nach bootloader_b und startet neu. In Slot B liest der
# Hersteller-U-Boot die Logos aus bootloader_b, das ab Werk leer ist (nur Nullen); ohne Logo
# schaltet er die Bildebene der Display-Engine nicht ein, und simpledrm zeigt nichts.
# Aufruf: sudo sh /home/user/werkzeuge/kopiere-bootloader-b.sh <sha256 von bootloader_a>
#   (Pruefsumme der PC-Sicherung backup/dsu-2026-10-28/bootloader_a.img)
set -eu
soll=$1
zeit() { echo "$(date +%H:%M:%S) $*"; }

quelle=""
for u in /sys/class/block/mmcblk0p*/uevent; do
	if grep -qx "PARTNAME=bootloader_a" "$u"; then
		quelle=/dev/$(basename "$(dirname "$u")")
	fi
done
if [ -z "$quelle" ]; then zeit "FEHLER: bootloader_a nicht gefunden"; exit 1; fi
dd if="$quelle" of=/tmp/bootloader_a.img bs=1M 2>/dev/null
ist=$(sha256sum < /tmp/bootloader_a.img | cut -d' ' -f1)
if [ "$ist" != "$soll" ]; then zeit "FEHLER: bootloader_a weicht von der Sicherung ab ($ist)"; exit 1; fi
zeit "bootloader_a ($quelle) gleicht der Sicherung"
sh /home/user/werkzeuge/schreibe-partition.sh bootloader_b /tmp/bootloader_a.img "$soll"
rm -f /tmp/bootloader_a.img
zeit "Neustart"
reboot
