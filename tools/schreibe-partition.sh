#!/bin/sh
# Laeuft auf dem Tablet als root: schreibt eine Abbild-Datei in eine eMMC-Partition (Suche nach
# dem GPT-Namen), sichert vorher den alten Inhalt nach /root/sicherung-<name>-<zeit>.img und liest
# danach ohne Seitencache zurueck, um die SHA-256 zu vergleichen.
# Aufruf: sudo sh schreibe-partition.sh <partitionsname> <datei> <sha256>
# Datei vorher vom PC kopieren, z. B.: cat x.img | pmos/tablet-ssh.sh 'cat > /tmp/x.img'
set -eu
name=$1
datei=$2
soll=$3
zeit() { echo "$(date +%H:%M:%S) $*"; }

geraet=""
for u in /sys/class/block/mmcblk0p*/uevent; do
	if grep -qx "PARTNAME=$name" "$u"; then
		geraet=/dev/$(basename "$(dirname "$u")")
	fi
done
if [ -z "$geraet" ]; then zeit "FEHLER: Partition $name nicht gefunden"; exit 1; fi
if grep -q "^$geraet " /proc/mounts; then zeit "FEHLER: $geraet ist eingehaengt"; exit 1; fi
groesse=$(stat -c%s "$datei")
if [ "$(blockdev --getsize64 "$geraet")" -lt "$groesse" ]; then zeit "FEHLER: $datei passt nicht in $geraet"; exit 1; fi
if [ "$(sha256sum < "$datei" | cut -d' ' -f1)" != "$soll" ]; then zeit "FEHLER: $datei hat nicht die erwartete Pruefsumme"; exit 1; fi

sicherung=/root/sicherung-$name-$(date +%Y%m%d-%H%M%S).img
dd if="$geraet" of="$sicherung" bs=1M 2>/dev/null
zeit "alter Inhalt von $name ($geraet) gesichert: $sicherung"
dd if="$datei" of="$geraet" bs=1M conv=fsync 2>&1 | tail -n 1
sync
echo 3 > /proc/sys/vm/drop_caches
ist=$(head -c "$groesse" "$geraet" | sha256sum | cut -d' ' -f1)
if [ "$ist" != "$soll" ]; then zeit "FEHLER: Pruefsumme nach dem Schreiben $ist"; exit 1; fi
zeit "$name ok ($groesse Bytes). FERTIG."
