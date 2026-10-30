#!/bin/bash
# Gegenstueck zu aktualisiere-kernel.sh (laeuft auf dem PC, ohne sudo): nimmt den Kernel aus dem
# linux-jeazans-c107-APK (vmlinuz ist ein EFI-zboot-Abbild mit gzip-Nutzlast, der Hersteller-bootm
# braucht das unkomprimierte Image), wartet auf das neue Initramfs des Tablets, prueft es, baut
# daraus mit dem DTB das Boot-Abbild (Adressen wie boot-pmos-emmc.img) und legt es dem Tablet hin:
# erst /tmp/boot-neu.img, nach erfolgreicher Pruefung als Signal /tmp/boot-neu.sha256.
# Aufruf: [ZUSATZ="param ..."] liefere-boot-abbild.sh <kernel.apk> <dtb> <name>
#   Ergebnis in fastboot/: Image-<name>, initramfs-<name>, boot-pmos-<name>.img, SHA256SUMS-<name>
#   ZUSATZ haengt Kernel-Parameter fuer Versuche an (etwa pd_ignore_unused).
#   INITRAMFS=<datei> nimmt dieses Initramfs, statt auf das des Tablets zu warten (fuer reine
#   DTB-Aenderungen bei unveraendertem Kernel; auf dem Tablet dann nur boot_b schreiben).
#   fbcon: Das Panel ist hochkant eingebaut (Logo und Android ORIENTATION_90), daher rotate:1.
#   clk_ignore_unused: Ohne ihn schaltet Linux unbenutzte Takte ab (u. a. msgbox, r-msgbox,
#   r-timer, r-apb1); dann haengt der PSCI-Reset der Firmware und erst der Watchdog startet neu
#   (19 s statt 2 s bis zur U-Boot-Begruessung, zweimal beobachtet am 29.10.).
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
APK=$1
DTB=$2
NAME=$3
SSH="$HIER/tablet-ssh.sh"
FB="$HIER/fastboot"
CMDLINE="console=ttyS0,115200 earlycon=uart8250,mmio32,0x02500000 loglevel=7 no_console_suspend panic=10 consoleblank=0 clk_ignore_unused fbcon=rotate:1,font:TER16x32 rw pmos_rootfsopts=defaults${ZUSATZ:+ $ZUSATZ}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tar -xzf "$APK" -C "$tmp" boot/vmlinuz 2>/dev/null || true
[ -f "$tmp/boot/vmlinuz" ] || { echo "FEHLER: kein boot/vmlinuz in $APK"; exit 1; }
python3 -I -c '
import struct, sys, zlib
d = open(sys.argv[1], "rb").read()
assert d[4:8] == b"zimg" and d[0x18:0x1c] == b"gzip", "kein EFI-zboot mit gzip"
off, size = struct.unpack("<II", d[8:16])
open(sys.argv[2], "wb").write(zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(d[off:off + size]))
' "$tmp/boot/vmlinuz" "$FB/Image-$NAME"
echo "Kernel: Image-$NAME ($(stat -c%s "$FB/Image-$NAME") Bytes)"

if [ -n "${INITRAMFS:-}" ]; then
	cp "$INITRAMFS" "$FB/initramfs-$NAME"
else
	echo "warte bis 15 min auf das Initramfs des Tablets ..."
	soll=""
	for _ in $(seq 1 180); do
		soll=$("$SSH" 'cat /tmp/initramfs-neu.sha256 2>/dev/null' || true)
		[ -n "$soll" ] && break
		sleep 5
	done
	[ -n "$soll" ] || { echo "FEHLER: kein Initramfs vom Tablet"; exit 1; }
	"$SSH" 'cat /tmp/initramfs-neu' > "$FB/initramfs-$NAME"
	[ "$(sha256sum < "$FB/initramfs-$NAME" | cut -d' ' -f1)" = "$soll" ] || { echo "FEHLER: Initramfs beschaedigt"; exit 1; }
fi

python3 "$HIER/baue-bootimg.py" --kernel "$FB/Image-$NAME" --ramdisk "$FB/initramfs-$NAME" \
	--dtb "$DTB" --cmdline "$CMDLINE" --out "$FB/boot-pmos-$NAME.img" --name arm64 \
	--kernel-offset 0x10000000 --ramdisk-offset 0x14000000 --dtb-offset 0x16000000
cp "$DTB" "$tmp/"
(cd "$FB" && sha256sum "boot-pmos-$NAME.img" "Image-$NAME" "initramfs-$NAME" > "SHA256SUMS-$NAME")
(cd "$tmp" && sha256sum "$(basename "$DTB")") >> "$FB/SHA256SUMS-$NAME"
boot_sha=$(sha256sum < "$FB/boot-pmos-$NAME.img" | cut -d' ' -f1)

"$SSH" 'cat > /tmp/boot-neu.img' < "$FB/boot-pmos-$NAME.img"
[ "$("$SSH" 'sha256sum < /tmp/boot-neu.img' | cut -d' ' -f1)" = "$boot_sha" ] || { echo "FEHLER: Uebertragung"; exit 1; }
echo "$boot_sha" | "$SSH" 'cat > /tmp/boot-neu.sha256.tmp && mv /tmp/boot-neu.sha256.tmp /tmp/boot-neu.sha256'
echo "boot-pmos-$NAME.img ($boot_sha) liegt auf dem Tablet, es schreibt jetzt boot_b und startet neu"
