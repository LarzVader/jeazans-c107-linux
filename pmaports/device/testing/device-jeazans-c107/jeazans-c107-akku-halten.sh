#!/bin/sh
# Haelt den Akku bei Dauerbetrieb am Netzteil bei rund 3,8 V (etwa 40-50 % Ladung),
# dort altert er am langsamsten. Die AXP717 kann die Ladespannung nicht unter 4,0 V
# einstellen (das steht im Geraetebaum als Sicherung), darum schaltet dieser Dienst das
# Laden ein und aus. Waehrend des Ladens (768 mA, Innenwiderstand rund 0,12 Ohm) zeigt der
# Akku etwa 0,1 V mehr als in Ruhe: Stopp bei 3,9 V ergibt rund 3,8 V Ruhespannung.
# Bei ausgeschaltetem Laden versorgt das Netzteil das Tablet allein, der Akku ruht.
# Andere Grenzen in /etc/default/jeazans-c107-akku-halten (START_MV, STOP_MV).
# Vor einer Reise: systemctl stop jeazans-c107-akku-halten laedt bis zur Grenze in
# voltage_max (4,0 V, per sysfs bis 4,2 V), der naechste Start haelt wieder.
AKKU=/sys/class/power_supply/axp20x-battery
START_MV=3750
STOP_MV=3900
[ -r /etc/default/jeazans-c107-akku-halten ] && . /etc/default/jeazans-c107-akku-halten

# Der Akku-Treiber ist ein Modul und kann spaeter kommen als dieser Dienst
until [ -w "$AKKU/status" ]; do sleep 5; done

zustand=""
while :; do
	mv=$(($(cat "$AKKU/voltage_now") / 1000))
	if [ "$mv" -ge "$STOP_MV" ] && [ "$zustand" != aus ]; then
		echo "Not charging" > "$AKKU/status"
		zustand=aus
		echo "Laden aus bei $mv mV"
	elif [ "$mv" -lt "$START_MV" ] && [ "$zustand" != an ]; then
		echo "Charging" > "$AKKU/status"
		zustand=an
		echo "Laden an bei $mv mV"
	fi
	sleep 120
done
