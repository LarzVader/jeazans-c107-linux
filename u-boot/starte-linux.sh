#!/bin/bash
# Startet postmarketOS per FEL (USB) auf dem Tablet, ohne den eMMC anzufassen:
# erst unser U-Boot (SPL mit DRAM-Init), dann Kernel, Initramfs und Geraetebaum
# direkt in den Arbeitsspeicher, dazu ein Boot-Skript, das U-Boot von selbst ausfuehrt.
#
# Aufruf: ./starte-linux.sh        -> normaler Start. Ohne Root-Partition wartet die
#                                     Initramfs 30 s und landet dann in der Debug-Shell.
#         ./starte-linux.sh debug  -> Initramfs haelt sofort in der Debug-Shell an.
#         ./starte-linux.sh vorbereiten -> nur Dateien und Boot-Skript erzeugen, nichts starten.
# Vorher ./konsole.sh in einem zweiten Terminal starten, sonst geht Ausgabe verloren.
# Debug-Shell: USB-Netz des Tablets, "telnet 172.16.42.1". Spaeter: ssh user@172.16.42.1
#
# Die Dateien kommen aus dem Rootfs-Chroot von pmbootstrap, nicht aus dem Abbild.
# Ohne TF-A gibt es kein PSCI: der Knoten /psci wird aus dem Geraetebaum entfernt,
# sonst stuerzt der Kernel beim ersten SMC ab. Folge: vorerst nur ein CPU-Kern.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
BIN="$HIER/build/u-boot-sunxi-with-spl.bin"
MKIMAGE="$HIER/build/tools/mkimage"
BOOT=~/.local/var/pmbootstrap/chroot_rootfs_jeazans-c107/boot
AUS="$HIER/linux"
MODUS=""
NUR_VORBEREITEN=""
for arg in "$@"; do
	case "$arg" in
		debug) MODUS=debug ;;
		vorbereiten) NUR_VORBEREITEN=1 ;;
		*) echo "Unbekanntes Argument: $arg (erlaubt: debug, vorbereiten)"; exit 1 ;;
	esac
done

# Ladeadressen = Vorgaben der U-Boot-Umgebung (kernel_addr_r, fdt_addr_r, scriptaddr, ramdisk_addr_r).
# U-Boot entpackt den Kernel nach kernel_comp_addr_r (0x44000000), dort stoert er nichts.
KERNEL_ADDR=0x40080000
FDT_ADDR=0x4fa00000
SCRIPT_ADDR=0x4fc00000
INITRD_ADDR=0x4ff00000

for d in "$BIN" "$MKIMAGE" "$BOOT/vmlinuz" "$BOOT/initramfs" "$BOOT/sun55i-a523-jeazans-c107.dtb"; do
	[ -e "$d" ] || { echo "Fehlt: $d"; exit 1; }
done

mkdir -p "$AUS"
python3 -I "$HIER/entpacke-kernel.py" "$BOOT/vmlinuz" "$AUS/Image.gz"
cp "$BOOT/initramfs" "$AUS/initramfs"
cp "$BOOT/sun55i-a523-jeazans-c107.dtb" "$AUS/c107.dtb"
initrd_groesse=$(printf '0x%x' "$(stat -c %s "$AUS/initramfs")")
uuids=$(grep -o 'pmos_boot_uuid=[^ ]* pmos_root_uuid=[^ ]*' "$BOOT/extlinux/extlinux.conf")

extra=""
[ "$MODUS" = "debug" ] && extra=" pmos.debug-shell"

# loglevel=7 statt "quiet": so erscheinen auch die Initramfs-Meldungen (via Kernel-Log) an der Konsole.
cat > "$AUS/linux-fel.txt" <<EOF
echo "== Jeazans C107: Linux per FEL, Kernel wird entpackt =="
setenv bootargs "console=ttyS0,115200 earlycon loglevel=7 no_console_suspend panic=10 consoleblank=0 rw $uuids pmos_rootfsopts=defaults$extra"
fdt addr \${fdt_addr_r}
fdt rm /psci
booti \${kernel_addr_r} \${ramdisk_addr_r}:$initrd_groesse \${fdt_addr_r}
EOF
"$MKIMAGE" -A arm64 -T script -C none -n "Linux per FEL" -d "$AUS/linux-fel.txt" "$AUS/linux-fel.scr" >/dev/null
echo "Boot-Skript:"; sed 's/^/    /' "$AUS/linux-fel.txt"
if [ -n "$NUR_VORBEREITEN" ]; then
	echo "Nur vorbereitet, nichts gestartet. Dateien liegen in $AUS"
	exit 0
fi

if adb get-state 2>/dev/null | grep -q device; then
	echo "Android laeuft - starte Tablet in den FEL-Modus ..."
	adb reboot efex
fi
echo "Warte auf FEL-Modus (USB 1f3a:efe8) ..."
until lsusb -d 1f3a:efe8 >/dev/null 2>&1; do sleep 1; done
sunxi-fel ver
# "uboot" laesst erst den SPL laufen (DRAM-Init), danach landen die "write"s im DRAM.
# Das .scr erkennt sunxi-fel und traegt seine Adresse im SPL-Kopf ein; U-Boot fuehrt es ueber bootcmd_fel aus.
sunxi-fel -v -p uboot "$BIN" \
	write "$KERNEL_ADDR" "$AUS/Image.gz" \
	write "$FDT_ADDR" "$AUS/c107.dtb" \
	write "$INITRD_ADDR" "$AUS/initramfs" \
	write "$SCRIPT_ADDR" "$AUS/linux-fel.scr"
echo "U-Boot gestartet und bootet Linux ueber das FEL-Skript. Ausgabe an der seriellen Konsole."
