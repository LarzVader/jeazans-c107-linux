#!/bin/bash
# Experiment: eigener Kernel + eigene Ramdisk/DTB ueber Slot B.
# do_bootm liest Ramdisk und DTB aus vendor_boot des AKTIVEN Slots. Also:
#   - vendor_boot_b <- vendor_boot-mini.img (unser DTB + mini-initramfs als Ramdisk)
#   - init_boot_b   <- init_boot-leer.img  (leere generische Ramdisk)
#   - Slot B aktiv schalten (fastboot set_active b, sonst misc-slotb.img flashen)
# boot_b behaelt das v2-Abbild (Kernel @0x50000000). Start am Prompt:
#   sunxi_flash read 0x60000000 boot_b ; bootm 0x60000000
# Rueckweg zu Android: fastboot set_active a  (oder misc aus dem Backup zuruecksichern).
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"; IMG="$HIER/fastboot"
fastboot devices | grep -q . || { echo "Kein fastboot-Geraet."; exit 1; }
echo "== vendor_boot_b <- vendor_boot-mini.img, init_boot_b <- init_boot-leer.img =="
fastboot flash vendor_boot_b "$IMG/vendor_boot-mini.img"
fastboot flash init_boot_b  "$IMG/init_boot-leer.img"
echo "== Slot B aktiv schalten =="
if fastboot set_active b 2>/dev/null; then
    echo "   set_active b OK"
else
    echo "   set_active nicht unterstuetzt -> misc-slotb.img flashen"
    fastboot flash misc "$IMG/misc-slotb.img"
fi
echo "== fertig. Am Prompt: sunxi_flash read 0x60000000 boot_b ; bootm 0x60000000 =="
