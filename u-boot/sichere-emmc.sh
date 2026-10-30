#!/bin/bash
# Liest den kompletten eMMC des Tablets ueber U-Boot "ums" (schreibgeschuetzt) aus.
# Voraussetzung: ./starte-fel.sh sichern  und die udev-Regel 52-tablet-linux.rules.
set -euo pipefail
ZIEL="${TABLET_BACKUP:-$HOME/dev/tablet-linux/backup}/emmc-komplett"
mkdir -p "$ZIEL"
DEV=""
for d in /sys/block/sd*; do
	[ -e "$d/device" ] || continue
	if udevadm info -q property -p "$d" | grep -q "ID_VENDOR_ID=1f3a"; then DEV="/dev/$(basename "$d")"; fi
done
[ -n "$DEV" ] || { echo "Tablet-eMMC nicht gefunden - laeuft ./starte-fel.sh sichern?"; exit 1; }
echo "Gefunden: $DEV ($(( $(cat /sys/block/$(basename $DEV)/size) * 512 / 1000000000 )) GB), schreibgeschuetzt: $(cat /sys/block/$(basename $DEV)/ro)"
dd if="$DEV" of="$ZIEL/emmc-c107.img" bs=4M status=progress conv=sparse
sha256sum "$ZIEL/emmc-c107.img" > "$ZIEL/emmc-c107.img.sha256"
echo "Fertig: $ZIEL/emmc-c107.img"
