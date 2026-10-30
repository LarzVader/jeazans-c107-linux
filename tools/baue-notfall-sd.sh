#!/bin/bash
# Baut das Abbild einer Rettungs-microSD fuer den Jeazans C107 aus der Sicherung vom 28.10.2026.
# Der BROM startet zuerst von SD. Die Karte traegt den Original-Bootloader (TOC0 ab 8 KiB,
# Hersteller-Paket ab 16 MiB + 16 KiB, beides aus emmc-anfang.img) und eine schlanke GPT mit
# (GPT mit 28 Eintraegen wie im Original, damit Sektor 16 fuer den TOC0 frei bleibt)
# nur den Partitionen, die der Hersteller-Bootloader fuer den Android-Start braucht
# (env_a, boot_a, vendor_boot_a, init_boot_a, dtbo_a, misc, vbmeta*, frp), mit Originalinhalt.
# super, metadata, userdata fehlen absichtlich: Android findet sie dann nur auf dem eMMC.
# Aufruf: baue-notfall-sd.sh [fastboot|rettung]
# Schreiben:  sudo dd if=notfall-sd.img of=/dev/sdX bs=4M status=progress conv=fsync
set -euo pipefail
B="${TABLET_BACKUP:-$HOME/dev/tablet-linux/backup/dsu-2026-10-28}"
AUS="$(dirname "$0")/fastboot/notfall-sd${1:+-$1}.img"
ENV="$B/env_a.img"
# Variante "fastboot": U-Boot-Umgebung mit bootcmd=fastboot, der Bootloader geht dann direkt in den fastboot-Modus
[ "${1:-}" = "fastboot" ] && ENV="$(dirname "$0")/fastboot/env_a-fastboot.img"
cd "$B" && sha256sum --quiet -c <(grep -E ' (emmc-anfang|env_a|boot_a|vendor_boot_a|init_boot_a|dtbo_a|misc|vbmeta_a|vbmeta_system_a|vbmeta_vendor_a|frp)\.img$' SHA256SUMS)

rm -f "$AUS"; truncate -s 336M "$AUS"
dd if="$B/emmc-anfang.img" of="$AUS" bs=1M conv=notrunc status=none
TYP=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7
sfdisk --no-reread --no-tell-kernel --quiet "$AUS" <<EOF
label: gpt
label-id: ab6f3888-569a-4926-9668-80941dcb40bc
unit: sectors
table-length: 28
first-lba: 73728
start=204800, size=512,    type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e47, name="env_a",           attrs="GUID:63"
start=205824, size=131072, type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e49, name="boot_a",          attrs="GUID:63"
start=467968, size=65536,  type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e4b, name="vendor_boot_a",   attrs="GUID:63"
start=599040, size=16384,  type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e4d, name="init_boot_a",     attrs="GUID:63"
start=615424, size=4096,   type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e5c, name="dtbo_a",          attrs="GUID:63"
start=619520, size=32768,  type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e50, name="misc",            attrs="GUID:63"
start=652288, size=256,    type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e51, name="vbmeta_a",        attrs="GUID:63"
start=652544, size=128,    type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e53, name="vbmeta_system_a", attrs="GUID:63"
start=652672, size=128,    type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e55, name="vbmeta_vendor_a", attrs="GUID:63"
start=652800, size=1024,   type=$TYP, uuid=a0085546-4166-744a-a353-fca9272b8e57, name="frp",             attrs="GUID:63"
EOF
# Variante "rettung": eigenes, selbst signiertes TOC0 (Rettungs-SPL, kopiert SD -> eMMC) statt des Hersteller-boot0
[ "${1:-}" = "rettung" ] && dd if="$(dirname "$0")/fastboot/rettung-toc0.bin" of="$AUS" bs=512 seek=16 conv=notrunc status=none
# env_b bekommt den Konsolen-Start (freie 512 Sektoren zwischen env_a und boot_a); die Rettungs-SPL kopiert sie nach eMMC env_b (LBA 205312)
[ "${1:-}" = "rettung" ] && dd if="$(dirname "$0")/fastboot/env_b-konsole.img" of="$AUS" bs=512 seek=205312 conv=notrunc status=none
schreibe() { dd if="$B/$1.img" of="$AUS" bs=512 seek="$2" conv=notrunc status=none; }
dd if="$ENV" of="$AUS" bs=512 seek=204800 conv=notrunc status=none; schreibe boot_a 205824; schreibe vendor_boot_a 467968; schreibe init_boot_a 599040
schreibe dtbo_a 615424; schreibe misc 619520; schreibe vbmeta_a 652288; schreibe vbmeta_system_a 652544
schreibe vbmeta_vendor_a 652672; schreibe frp 652800
sha256sum "$AUS" > "$AUS.sha256"
echo "fertig: $AUS ($(stat -c %s "$AUS") Bytes, belegt $(du -h "$AUS" | cut -f1))"
