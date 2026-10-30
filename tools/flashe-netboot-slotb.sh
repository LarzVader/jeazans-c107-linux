#!/bin/bash
# Flasht NUR boot_b mit dem pmOS-Netboot-Abbild (Kernel r1 + pmOS-Initramfs mit Netboot-Hook).
# Seit 29.10. liegt normal boot-pmos-emmc.img (Root auf dem eMMC) in boot_b; dies ist der Rueckweg zum Netboot.
# Slot A (Android) bleibt unberuehrt. Voraussetzung: Tablet am U-Boot-Prompt "fastboot" getippt.
# Danach "fastboot reboot": der env_b-Autostart startet pmOS selbst (Variable "linux": init_boot aus
# der A/B-Liste nehmen, sonst nimmt bootm die leere Ramdisk aus init_boot_b; dazu
# watchdog.stop_on_reboot=0; dann sunxi_flash read 0x60000000 boot_b; bootm 0x60000000).
# Am Prompt von Hand: "run linux".
# Auf dem PC vorher: pmos/netboot-serve.sh
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
IMG="$HIER/fastboot/boot-pmos-netboot.img"
[ -f "$IMG" ] || { echo "Fehlt: $IMG"; exit 1; }
(cd "$HIER/fastboot" && sha256sum --quiet -c SHA256SUMS-netboot) || { echo "Pruefsummen in SHA256SUMS-netboot passen nicht."; exit 1; }
fastboot devices | grep -q . || { echo "Kein fastboot-Geraet sichtbar."; exit 1; }
echo "== boot_b <- $(basename "$IMG") ($(stat -c%s "$IMG") Bytes) =="
fastboot flash boot_b "$IMG"
echo "== boot_b geflasht. Weiter mit 'fastboot reboot', der Autostart startet pmOS. =="
