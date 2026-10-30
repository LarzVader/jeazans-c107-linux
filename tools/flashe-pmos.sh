#!/bin/bash
# Flasht unseren Kernel in Slot A des Jeazans C107 (Hersteller-Bootloader bleibt):
#   vendor_boot_a <- vendor_boot-pmos.img (pmOS-Initramfs + unser Geraetebaum)
#   init_boot_a   <- init_boot-leer.img   (leere Ramdisk, sonst gewinnt Androids /init)
#   boot_a        <- boot-pmos.img        (Kernel unkomprimiert, 54 MB, Sparse-Stueckelung)
#                    oder boot-pmos-gz.img mit "gz" (19,5 MB, falls der Bootloader gzip kann)
# Optional "dtbo": dtbo_a <- dtbo-leer.img (Overlays des Herstellers passen nicht zu unserem DTB)
# Rueckweg: ./stelle-android-wieder-her.sh
# Aufruf: ./flashe-pmos.sh [gz] [dtbo]
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
IMG="$HIER/fastboot"
BOOT="$IMG/boot-pmos.img"
DTBO=""
for arg in "$@"; do
	case "$arg" in
		gz) BOOT="$IMG/boot-pmos-gz.img" ;;
		dtbo) DTBO="$IMG/dtbo-leer.img" ;;
		*) echo "Unbekannt: $arg"; exit 1 ;;
	esac
done
cd "$IMG" && sha256sum --quiet -c SHA256SUMS-pmos
[ -f "${TABLET_BACKUP:-$HOME/dev/tablet-linux/backup/dsu-2026-10-28}/boot_a.img" ] || { echo "Keine Sicherung gefunden, Abbruch."; exit 1; }

"$HIER/starte-fastboot.sh" info >/dev/null 2>&1 || true
fastboot devices | grep -q . || { echo "Kein fastboot-Geraet."; exit 1; }
echo "== Flashe vendor_boot_a, init_boot_a, boot_a ($(basename "$BOOT"))${DTBO:+, dtbo_a} =="
fastboot flash vendor_boot_a "$IMG/vendor_boot-pmos.img"
fastboot flash init_boot_a "$IMG/init_boot-leer.img"
fastboot flash boot_a "$BOOT"
[ -n "$DTBO" ] && fastboot flash dtbo_a "$DTBO"
echo "== fertig geflasht, Neustart =="
fastboot reboot
