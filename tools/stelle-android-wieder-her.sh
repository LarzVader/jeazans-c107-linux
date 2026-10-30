#!/bin/bash
# Stellt Slot A des Jeazans C107 aus der Sicherung vom 28.10.2026 wieder her
# (boot_a, vendor_boot_a, init_boot_a, dtbo_a). Tablet muss im fastboot-Modus sein
# oder per adb erreichbar; sonst: Power lange druecken, beim Start Lautstaerke-? fuer fastboot,
# oder "adb reboot bootloader" aus Android.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
B="${TABLET_BACKUP:-$HOME/dev/tablet-linux/backup/dsu-2026-10-28}"
cd "$B" && sha256sum --quiet -c <(grep -E ' (boot_a|vendor_boot_a|init_boot_a|dtbo_a)\.img$' SHA256SUMS)
"$HIER/starte-fastboot.sh" info >/dev/null 2>&1 || true
fastboot devices | grep -q . || { echo "Kein fastboot-Geraet."; exit 1; }
echo "== Stelle Original wieder her =="
fastboot flash dtbo_a "$B/dtbo_a.img"
fastboot flash init_boot_a "$B/init_boot_a.img"
fastboot flash vendor_boot_a "$B/vendor_boot_a.img"
fastboot flash boot_a "$B/boot_a.img"
echo "== fertig, Neustart nach Android =="
fastboot reboot
