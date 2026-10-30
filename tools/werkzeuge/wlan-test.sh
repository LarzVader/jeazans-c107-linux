#!/bin/sh
# Laeuft auf dem Tablet als root: WLAN-Fehlersuche ohne Neustart.
# 1. Debugmeldungen des MMC-Kerns an, 2. PL7 (power_en der Funkmodul-Versorgung laut
# Hersteller-rfkill) mit gpio-halten auf high halten (eigene Sitzung, bleibt nach dem Ende
# des Skripts aktiv), 3. mmc1 (4021000.mmc) neu anbinden, 4. Meldungen und SDIO-Geraete zeigen.
# Aufruf: sudo sh /home/user/werkzeuge/wlan-test.sh [ohne-pl7]
W=/home/user/werkzeuge
zeit() { echo "$(date +%H:%M:%S) $*"; }

mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
echo 'file drivers/mmc/core/* +p' > /sys/kernel/debug/dynamic_debug/control && zeit "MMC-Debug an"
if [ "${1:-}" != "ohne-pl7" ]; then
	setsid "$W/gpio-halten" 7022000 7 1 > "$W/gpio-halten.log" 2>&1 &
	sleep 1
	cat "$W/gpio-halten.log"
fi
grep -i -E 'gpio-halten|vcc-wifi|7022000|PL7|PM1' /sys/kernel/debug/gpio

zeit "binde mmc1 neu an"
echo 4021000.mmc > /sys/bus/platform/drivers/sunxi-mmc/unbind
sleep 1
dmesg -C
echo 4021000.mmc > /sys/bus/platform/drivers/sunxi-mmc/bind
sleep 6
zeit "Kernelmeldungen:"
dmesg | grep -v -E 'audit|apparmor' | cut -c1-160 | tail -60
zeit "SDIO-Geraete:"
for d in /sys/bus/sdio/devices/*; do
	[ -e "$d/vendor" ] && echo "$d vendor=$(cat "$d/vendor") device=$(cat "$d/device")"
done
grep -i -E 'gpio-halten|vcc-wifi' /sys/kernel/debug/gpio
ip -br link
