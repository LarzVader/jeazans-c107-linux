#!/bin/sh
# Laeuft auf dem Tablet ohne root: meldet jede Lage des Sensors, die 3 Sekunden ruhig bleibt.
# Rohwerte 1000 = rund 1 g. Die Achse z zaehlt erst ab 0,8 g, damit angelehnt noch als aufrecht gilt.
D=$(dirname "$(grep -l sc7a20 /sys/bus/iio/devices/iio:device*/name)")
letzte=""
kandidat=""
n=0
while :; do
	x=$(cat "$D/in_accel_x_raw")
	y=$(cat "$D/in_accel_y_raw")
	z=$(cat "$D/in_accel_z_raw")
	ax=${x#-}
	ay=${y#-}
	az=${z#-}
	if [ "$az" -ge 800 ]; then
		a=z
		w=$z
	elif [ "$ax" -ge "$ay" ]; then
		a=x
		w=$x
	else
		a=y
		w=$y
	fi
	if [ "$w" -lt 0 ]; then lage="-$a"; else lage="+$a"; fi
	if [ "$lage" = "$kandidat" ]; then n=$((n + 1)); else kandidat=$lage; n=0; fi
	if [ "$n" -ge 3 ] && [ "$lage" != "$letzte" ]; then
		echo "$(date +%H:%M:%S) Lage $lage: x=$x y=$y z=$z"
		letzte=$lage
	fi
	sleep 1
done
