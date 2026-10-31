#!/bin/sh
# Haelt den Akku bei Dauerbetrieb am Netzteil bei rund 50 % (in Ruhe rund 3,83 V), dort
# altert er langsam. Die AXP717 kann die Ladespannung nicht unter 4,0 V einstellen (das
# steht im Geraetebaum als Sicherung), darum schaltet dieser Dienst das Laden ein und aus.
# Massgeblich ist die Prozentanzeige des Messchips, nicht die Spannung: Waehrend des
# Ladens zeigt der Akku rund 0,1 V mehr als in Ruhe, ein Stopp bei 3,9 V ergab beim Laden
# von unten nur 34 % (3,79 V in Ruhe).
# Bei ausgeschaltetem Laden versorgt das Netzteil das Tablet allein, der Akku ruht.
# Andere Grenzen in /etc/default/jeazans-c107-akku-halten (START_PROZENT, STOP_PROZENT).
# Vor einer Reise: systemctl stop jeazans-c107-akku-halten laedt bis zur Grenze in
# voltage_max (4,0 V, per sysfs bis 4,2 V), der naechste Start haelt wieder.
AKKU=/sys/class/power_supply/axp20x-battery
START_PROZENT=45
STOP_PROZENT=50
[ -r /etc/default/jeazans-c107-akku-halten ] && . /etc/default/jeazans-c107-akku-halten

# Der Akku-Treiber ist ein Modul und kann spaeter kommen als dieser Dienst
until [ -w "$AKKU/status" ]; do sleep 5; done

zustand=""
while :; do
	prozent=$(cat "$AKKU/capacity")
	mv=$(($(cat "$AKKU/voltage_now") / 1000))
	if [ "$prozent" -ge "$STOP_PROZENT" ] && [ "$zustand" != aus ]; then
		echo "Not charging" > "$AKKU/status"
		zustand=aus
		echo "Laden aus bei $prozent % ($mv mV)"
	elif [ "$prozent" -lt "$START_PROZENT" ] && [ "$zustand" != an ]; then
		echo "Charging" > "$AKKU/status"
		zustand=an
		echo "Laden an bei $prozent % ($mv mV)"
	fi
	sleep 120
done
