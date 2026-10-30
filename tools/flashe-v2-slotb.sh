#!/bin/bash
# Flasht NUR boot_b mit unserem eigenstaendigen v2-Android-Abbild (Kernel + Mini-Initramfs + DTB im Image).
# Slot A (Android) bleibt unberuehrt. Voraussetzung: Tablet am U-Boot-Prompt "fastboot" getippt.
# Danach am Prompt starten (Abbild explizit laden, nicht ueber die A/B-Automatik):
#   sunxi_flash read 0x60000000 boot_b
#   bootm 0x60000000
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
IMG="$HIER/fastboot/boot-v2-arm64.img"
[ -f "$IMG" ] || { echo "Fehlt: $IMG"; exit 1; }
(cd "$HIER/fastboot" && sha256sum --quiet -c SHA256SUMS-v2) || { echo "Pruefsumme von boot-v2-arm64.img passt nicht."; exit 1; }
fastboot devices | grep -q . || { echo "Kein fastboot-Geraet sichtbar."; exit 1; }
echo "== boot_b <- $(basename "$IMG") ($(stat -c%s "$IMG") Bytes) =="
fastboot flash boot_b "$IMG"
echo "== boot_b geflasht. Am Prompt: sunxi_flash read 0x60000000 boot_b ; bootm 0x60000000 =="
