#!/bin/bash
# Bereitet den Umzug von pmOS auf den eMMC vor (Root im userdata, pmOS-Standard fuer Android-Geraete:
# das Initramfs findet pmOS_boot/pmOS_root als Subpartitionen in userdata und vergroessert Root beim
# ersten Start auf die ganze Partition). Voraussetzung: Abbild frisch gebaut ohne Netboot-Hook:
#   pmbootstrap chroot -r -- apk del postmarketos-mkinitfs-hook-netboot && pmos/baue-abbild.sh --no-split
# Schritte: pruefen, dass vmlinuz im Rootfs dem Kernel Image-r1 entspricht (sonst passen die Module
# nicht), Initramfs aus dem Rootfs-Chroot holen (ohne Netboot-Hook), Boot-Abbild boot-pmos-emmc.img
# bauen (wie boot-pmos-netboot.img, nur andere Ramdisk), Abbild gzip-komprimiert nach pmos/emmc/
# legen und pmos/emmc/schreibe-emmc.sh mit Groessen und Pruefsummen erzeugen.
# Danach auf dem PC pmos/emmc-serve.sh, auf dem Tablet schreibe-emmc.sh als root (siehe dort).
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
WORK=~/.local/var/pmbootstrap
FB="$HIER/fastboot"
ZIEL="$HIER/emmc"
ABBILD="$WORK/chroot_native/home/pmos/rootfs/jeazans-c107.img"
ROOTFS_BOOT="$WORK/chroot_rootfs_jeazans-c107/boot"
CMDLINE="console=ttyS0,115200 earlycon=uart8250,mmio32,0x02500000 loglevel=7 no_console_suspend panic=10 consoleblank=0 rw pmos_rootfsopts=defaults"
sha() { sha256sum < "$1" | cut -d' ' -f1; }

# vmlinuz ist ein EFI-zboot-Abbild ("zimg"): gzip-Nutzlast ab Byte-Offset [8], Laenge [12]
vmlinuz_sha=$(python3 -I -c '
import hashlib, struct, sys, zlib
d = open(sys.argv[1], "rb").read()
assert d[4:8] == b"zimg" and d[0x18:0x1c] == b"gzip", "kein EFI-zboot mit gzip"
off, size = struct.unpack("<II", d[8:16])
print(hashlib.sha256(zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(d[off:off + size])).hexdigest())
' "$ROOTFS_BOOT/vmlinuz")
[ "$vmlinuz_sha" = "$(sha "$FB/Image-r1")" ] || { echo "FEHLER: vmlinuz im Rootfs ist nicht Image-r1"; exit 1; }
WORLD="$WORK/chroot_rootfs_jeazans-c107/etc/apk/world"
! grep -qx postmarketos-mkinitfs-hook-netboot "$WORLD" || { echo "FEHLER: Netboot-Hook noch im Rootfs"; exit 1; }
[ "$ABBILD" -nt "$WORLD" ] || { echo "FEHLER: Abbild ist aelter als das Rootfs (nicht neu gebaut?)"; exit 1; }
[ "$(sfdisk -d "$ABBILD" | grep -c '^/')" -eq 2 ] || { echo "FEHLER: Abbild hat nicht genau 2 Partitionen"; exit 1; }

cp "$ROOTFS_BOOT/initramfs" "$FB/initramfs-emmc-r1"
liste=$(zstd -dc "$FB/initramfs-emmc-r1" | cpio -t 2>/dev/null)
if grep -q netboot <<< "$liste"; then
	echo "FEHLER: Initramfs enthaelt noch den Netboot-Hook"; exit 1
fi
python3 "$HIER/baue-bootimg.py" --kernel "$FB/Image-r1" --ramdisk "$FB/initramfs-emmc-r1" \
	--dtb "$FB/c107-bl31.dtb" --cmdline "$CMDLINE" --out "$FB/boot-pmos-emmc.img" --name arm64 \
	--kernel-offset 0x10000000 --ramdisk-offset 0x14000000 --dtb-offset 0x16000000
(cd "$FB" && sha256sum boot-pmos-emmc.img Image-r1 initramfs-emmc-r1 c107-bl31.dtb > SHA256SUMS-emmc)

mkdir -p "$ZIEL"
cp "$FB/boot-pmos-emmc.img" "$ZIEL/"
echo "== komprimiere $(basename "$ABBILD") ($(stat -c%s "$ABBILD") Bytes) =="
if command -v pigz > /dev/null; then pigz -1 -c "$ABBILD"; else gzip -1 -c "$ABBILD"; fi > "$ZIEL/pmos-emmc.img.gz"
ABBILD_GROESSE=$(stat -c%s "$ABBILD")
ABBILD_SHA=$(sha "$ABBILD")
BOOT_GROESSE=$(stat -c%s "$FB/boot-pmos-emmc.img")
BOOT_SHA=$(sha "$FB/boot-pmos-emmc.img")

cat > "$ZIEL/schreibe-emmc.sh" << EOF
#!/bin/sh
# Laeuft auf dem Tablet als root: schreibt pmOS nach userdata (mmcblk0p28) und danach das
# eMMC-Boot-Abbild nach boot_b (mmcblk0p6). Beides wird ohne Seitencache zurueckgelesen und mit der
# Pruefsumme verglichen; stimmt userdata nicht, bleibt boot_b (Netboot) unveraendert.
# Erzeugt von pmos/baue-emmc-abbilder.sh. Aufruf vom PC (pmos/emmc-serve.sh muss laufen):
#   pmos/tablet-ssh.sh -t 'wget -q -O /tmp/schreibe-emmc.sh http://172.16.42.2:8000/schreibe-emmc.sh && sudo sh /tmp/schreibe-emmc.sh'
set -eu
SERVER=http://172.16.42.2:8000
ABBILD_GROESSE=$ABBILD_GROESSE
ABBILD_SHA=$ABBILD_SHA
BOOT_GROESSE=$BOOT_GROESSE
BOOT_SHA=$BOOT_SHA

zeit() { echo "\$(date +%H:%M:%S) \$*"; }
pruefe_name() {
	grep -qx "PARTNAME=\$2" "/sys/class/block/\$1/uevent" || { zeit "FEHLER: \$1 ist nicht \$2, Abbruch"; exit 1; }
}
pruefe_name mmcblk0p28 userdata
pruefe_name mmcblk0p6 boot_b
if grep -q '^/dev/mmcblk0' /proc/mounts; then zeit "FEHLER: eine eMMC-Partition ist eingehaengt, Abbruch"; exit 1; fi
[ "\$(blockdev --getsize64 /dev/mmcblk0p28)" -ge "\$ABBILD_GROESSE" ] || { zeit "FEHLER: userdata zu klein"; exit 1; }

zeit "hole Boot-Abbild"
wget -q -O /tmp/boot-pmos-emmc.img "\$SERVER/boot-pmos-emmc.img"
[ "\$(sha256sum < /tmp/boot-pmos-emmc.img | cut -d' ' -f1)" = "\$BOOT_SHA" ] || { zeit "FEHLER: Boot-Abbild beschaedigt"; exit 1; }

zeit "schreibe userdata (pmOS-Abbild, \$ABBILD_GROESSE Bytes, dauert einige Minuten) ..."
wget -q -O- "\$SERVER/pmos-emmc.img.gz" | gzip -dc | dd of=/dev/mmcblk0p28 bs=4M conv=fsync 2>&1 | tail -n 1
sync
echo 3 > /proc/sys/vm/drop_caches
zeit "pruefe userdata ..."
ist=\$(head -c "\$ABBILD_GROESSE" /dev/mmcblk0p28 | sha256sum | cut -d' ' -f1)
[ "\$ist" = "\$ABBILD_SHA" ] || { zeit "FEHLER: userdata-Pruefsumme \$ist, boot_b bleibt unveraendert"; exit 1; }
zeit "userdata ok"

zeit "schreibe boot_b ..."
dd if=/tmp/boot-pmos-emmc.img of=/dev/mmcblk0p6 bs=1M conv=fsync 2>&1 | tail -n 1
sync
echo 3 > /proc/sys/vm/drop_caches
ist=\$(head -c "\$BOOT_GROESSE" /dev/mmcblk0p6 | sha256sum | cut -d' ' -f1)
[ "\$ist" = "\$BOOT_SHA" ] || { zeit "FEHLER: boot_b-Pruefsumme \$ist"; exit 1; }
zeit "boot_b ok. FERTIG. Neustart: sudo reboot"
EOF
(cd "$ZIEL" && sha256sum pmos-emmc.img.gz boot-pmos-emmc.img schreibe-emmc.sh > SHA256SUMS)
ls -la "$ZIEL"
echo "== fertig: Abbild $ABBILD_GROESSE Bytes ($ABBILD_SHA), boot-pmos-emmc.img $BOOT_GROESSE Bytes =="
