#!/bin/bash
# Flasht NUR env_b (U-Boot-Umgebung von Slot B). Voraussetzung: Tablet am U-Boot-Prompt "fastboot" getippt.
#   flashe-env-b.sh            -> env_b-autostart.img: Begruessung, 5 s Strg+C-Fenster, dann startet pmOS
#                                 (linux: ab_partition_list ohne init_boot, bootargs watchdog.stop_on_reboot=0,
#                                 sunxi_flash read 0x60000000 boot_b, bootm 0x60000000)
#   flashe-env-b.sh konsole    -> env_b-konsole.img (Rueckweg): nur Begruessung, bleibt am Prompt
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
case "${1:-autostart}" in
	autostart) IMG="$HIER/fastboot/env_b-autostart.img" ;;
	konsole) IMG="$HIER/fastboot/env_b-konsole.img" ;;
	*) echo "Aufruf: $0 [autostart|konsole]"; exit 1 ;;
esac
(cd "$HIER/fastboot" && sha256sum --quiet -c SHA256SUMS-env-b) || { echo "Pruefsummen in SHA256SUMS-env-b passen nicht."; exit 1; }
fastboot devices | grep -q . || { echo "Kein fastboot-Geraet sichtbar."; exit 1; }
echo "== env_b <- $(basename "$IMG") =="
fastboot flash env_b "$IMG"
echo "== env_b geflasht. Weiter mit 'fastboot reboot'. =="
