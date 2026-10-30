#!/bin/bash
# Baut den Geraetebaum, den der Hersteller-bootm aus vendor_boot_b an den Kernel uebergibt:
# sun55i-a523-jeazans-c107.dts (Standard: die Fassung in pmaports/ dieses Repos) mit den DT-Quellen von
# Linux 7.2 (der Stable-Patch 7.2.11 aendert dort nichts an A523/dt-bindings), dazu wie in
# c107-bl31.dtb der Speicherknoten (4 GiB) und zwei /memreserve/ (BL31/OP-TEE, 0xb6000000). Den
# Bildspeicher des U-Boot (0xb1f0e000) reserviert die DTS selbst mit no-map; ein /memreserve/ an
# derselben Stelle (frueher 0xb1f13000, Androids Adresse) liesse das no-map scheitern (-EBUSY).
# Aufruf: baue-dtb.sh [ausgabe.dtb] [quelle.dts]   (Standard: fastboot/c107-wlan-bl31.dtb)
#         Mit OHNE_BL31=1 entsteht der reine DTB (wie im Kernelpaket), etwa zum Vergleich.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
AUS="${1:-$HIER/fastboot/c107-wlan-bl31.dtb}"
DTS="${2:-$HIER/../pmaports/device/testing/linux-jeazans-c107/sun55i-a523-jeazans-c107.dts}"
TAR=~/.local/var/pmbootstrap/cache_distfiles/linux-7.2.tar.xz
BAUM="$HIER/dtb-bau/linux-7.2"
ALLW="$BAUM/arch/arm64/boot/dts/allwinner"

if [ ! -d "$ALLW" ]; then
	mkdir -p "$HIER/dtb-bau"
	tar -xJf "$TAR" -C "$HIER/dtb-bau" linux-7.2/arch/arm64/boot/dts/allwinner \
		linux-7.2/include/dt-bindings linux-7.2/scripts/dtc/include-prefixes
fi
# dt-bindings/input/linux-event-codes.h ist ein Link auf diese Datei
if [ ! -f "$BAUM/include/uapi/linux/input-event-codes.h" ]; then
	tar -xJf "$TAR" -C "$HIER/dtb-bau" linux-7.2/include/uapi/linux/input-event-codes.h
fi
cp "$DTS" "$ALLW/sun55i-a523-jeazans-c107.dts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$BAUM/include" -I "$ALLW" \
	-I "$BAUM/scripts/dtc/include-prefixes" "$ALLW/sun55i-a523-jeazans-c107.dts" \
	| sed '/^#/d' > "$tmp/vor.dts"
if [ "${OHNE_BL31:-0}" = 1 ]; then
	cp "$tmp/vor.dts" "$tmp/c107.dts"
else
	{
		echo '/dts-v1/;'
		echo '/memreserve/ 0x48000000 0x01000000;'
		echo '/memreserve/ 0xb6000000 0x0a000000;'
		sed '0,/\/dts-v1\/;/{//d}' "$tmp/vor.dts"
		echo '/ { memory@40000000 { device_type = "memory"; reg = <0x00 0x40000000 0x01 0x00>; }; };'
	} > "$tmp/c107.dts"
fi
dtc -q -I dts -O dtb -o "$AUS" "$tmp/c107.dts"
echo "$AUS: $(stat -c%s "$AUS") Bytes"
