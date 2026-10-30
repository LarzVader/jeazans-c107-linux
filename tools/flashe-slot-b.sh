#!/bin/bash
# Flasht unsere Abbilder in Slot B des Jeazans C107; Android in Slot A bleibt unberuehrt.
# Voraussetzung: Tablet im fastboot-Modus (am U-Boot-Prompt "fastboot" oder "adb reboot bootloader").
# vbmeta*_b bekommen Kopien der Slot-A-Originale, damit der Bootloader gueltige Strukturen findet;
# die Pruefsummen passen nicht, das laesst der entsperrte Bootloader (orange) zu.
# Starten danach am U-Boot-Prompt: setenv slot_suffix _b; run setargs_mmc boot_normal
# Aufruf: ./flashe-slot-b.sh [gz]   (gz: Kernel als Image.gz statt unkomprimiert)
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
IMG="$HIER/fastboot"
B="${TABLET_BACKUP:-$HOME/dev/tablet-linux/backup/dsu-2026-10-28}"
BOOT="$IMG/boot-pmos.img"
[ "${1:-}" = "gz" ] && BOOT="$IMG/boot-pmos-gz.img"

(cd "$IMG" && sha256sum --quiet -c SHA256SUMS-pmos)
(cd "$B" && sha256sum --quiet -c <(grep -E ' (vbmeta_a|vbmeta_system_a|vbmeta_vendor_a)\.img$' SHA256SUMS))
fastboot devices | grep -q . || { echo "Kein fastboot-Geraet."; exit 1; }

echo "== Slot B: boot_b ($(basename "$BOOT")), vendor_boot_b, init_boot_b, dtbo_b, vbmeta*_b =="
fastboot flash boot_b "$BOOT"
fastboot flash vendor_boot_b "$IMG/vendor_boot-pmos.img"
fastboot flash init_boot_b "$IMG/init_boot-leer.img"
fastboot flash dtbo_b "$IMG/dtbo-leer.img"
fastboot flash vbmeta_b "$B/vbmeta_a.img"
fastboot flash vbmeta_system_b "$B/vbmeta_system_a.img"
fastboot flash vbmeta_vendor_b "$B/vbmeta_vendor_a.img"
echo "== Slot B geflasht =="
