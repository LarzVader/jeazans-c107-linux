#!/bin/bash
# Meldet 60 s lang jede Aenderung der Allwinner-USB-Geraete (fastboot 1010, FEL efe8, Android 4ee7).
alt=""
for i in $(seq 1 ${1:-60}); do
	neu=$(lsusb | grep -i '1f3a' | sed 's/Bus.*ID //' | tr '\n' ';')
	[ "$neu" != "$alt" ] && { echo "$(date +%T) ${neu:-kein Tablet-Geraet}"; alt="$neu"; }
	sleep 1
done
