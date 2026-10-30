#!/bin/bash
# Startet das selbst gebaute U-Boot per FEL (USB) auf dem Tablet.
# Aufruf: ./starte-fel.sh            -> U-Boot mit Konsole am microSD-Slot
#         ./starte-fel.sh sichern    -> zusaetzlich eMMC schreibgeschuetzt per USB freigeben (ums)
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
# Anderes U-Boot-Binary waehlbar, z. B. UBOOT_BIN=build-ohne-gic/u-boot-sunxi-with-spl.bin ./starte-fel.sh
BIN="${UBOOT_BIN:-$HIER/build/u-boot-sunxi-with-spl.bin}"
SKRIPT=""
[ "${1:-}" = "sichern" ] && SKRIPT="$HIER/build/ums-sichern.scr"

if adb get-state 2>/dev/null | grep -q device; then
	echo "Android laeuft - starte Tablet in den FEL-Modus ..."
	adb reboot efex
fi
echo "Warte auf FEL-Modus (USB 1f3a:efe8) ..."
until lsusb -d 1f3a:efe8 >/dev/null 2>&1; do sleep 1; done
sunxi-fel ver
if [ -n "$SKRIPT" ]; then
	sunxi-fel -v -p uboot "$BIN" write 0x43100000 "$SKRIPT"
else
	sunxi-fel -v -p uboot "$BIN"
fi
echo "U-Boot gestartet. Meldungen erscheinen an der seriellen Konsole (./konsole.sh)."
