#!/bin/bash
# Umgang mit dem Hersteller-Bootloader (fastboot, USB 1f3a:1010) des Jeazans C107.
# Aufruf: ./starte-fastboot.sh info          -> in den fastboot-Modus, getvar all auslesen (nur lesen)
#         ./starte-fastboot.sh boot <image>  -> Boot-Image per "fastboot boot" starten (kein Flashen)
#         ./starte-fastboot.sh reboot        -> zurueck nach Android
# Vorher ./konsole.sh bzw. konsole-zeit.py am CP2102, um den Kernelstart mitzulesen.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
MODUS="${1:-info}"

in_fastboot() {
	if fastboot devices 2>/dev/null | grep -q .; then return; fi
	if adb get-state 2>/dev/null | grep -q device; then
		echo "Android laeuft - Neustart in den Bootloader ..."
		adb reboot bootloader
	fi
	echo "Warte auf fastboot ..."
	local n=0
	until fastboot devices 2>/dev/null | grep -q .; do
		sleep 1; n=$((n + 1))
		[ "$n" -gt 60 ] && { echo "Kein fastboot-Geraet nach 60 s (lsusb: $(lsusb | grep -i -c 1f3a) Allwinner-Geraete)"; exit 1; }
	done
	fastboot devices
}

case "$MODUS" in
	info)
		in_fastboot
		datei="$HIER/fastboot/getvar-$(date +%Y-%m-%d_%H-%M).txt"
		mkdir -p "$HIER/fastboot"
		fastboot getvar all 2>&1 | tee "$datei" | grep -v '^$' | head -n 80
		echo "gespeichert: $datei"
		;;
	boot)
		img="${2:?Boot-Image fehlt}"
		in_fastboot
		echo "Starte $img per fastboot boot ($(stat -c %s "$img") Bytes) ..."
		fastboot boot "$img"
		;;
	reboot)
		fastboot reboot
		;;
	*)
		echo "Unbekannt: $MODUS"; exit 1
		;;
esac
