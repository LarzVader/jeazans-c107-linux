#!/bin/sh
# Laeuft auf dem Tablet ohne root: schreibt alle N Sekunden die Akku-Messwerte als Tabelle.
# Aufruf: nohup sh ~/werkzeuge/akku-mitschreiben.sh [sekunden] >> ~/akku-log.txt 2>&1 &
# ts_roh in halben mV (Fuehler: 10 kOhm NTC, rund 1000 = 25 Grad, weniger = waermer),
# strom_roh wie vom ADC gemeldet (Treiber-Kommentar: unbekannter Versatz um 450 mA).
n=${1:-20}
B=/sys/class/power_supply/axp20x-battery
U=/sys/class/power_supply/axp20x-usb
# Die IIO-Nummer wechselt (mit Lagesensor ist es device1), und per Geraetebaum hat der ADC keinen Namen
A=$(echo /sys/devices/platform/soc/7081400.i2c/i2c-*/*-0034/axp717-adc/iio:device*)
echo "zeit status soc% usb akku_mV vsys_mV vbus_mV strom_roh ts_roh die_roh"
while :; do
	echo "$(date +%H:%M:%S) $(sed 's/ /_/' "$B/status") $(cat "$B/capacity") $(cat "$U/online")" \
		"$(cat "$A/in_voltage0_raw") $(cat "$A/in_voltage3_raw") $(cat "$A/in_voltage2_raw")" \
		"$(cat "$A/in_current5_raw") $(cat "$A/in_voltage1_raw") $(cat "$A/in_temp4_raw")"
	sleep "$n"
done
