#!/bin/bash
# Baut U-Boot fuer das Jeazans-C107-Tablet (FEL-Betrieb, Konsole ueber microSD-Slot).
# Aufruf: ./baue-u-boot.sh [pfad/zu/bl31.bin]  (BL31 optional; fuer den A523 gibt es noch kein TF-A im Hauptzweig)
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
UBOOT="${UBOOT_SRC:-$HIER/../src/u-boot}"  # Mainline-U-Boot-Checkout
OUT="$HIER/build"
BL31_DATEI="${1:-}"

cp "$HIER/sun55i-a523-jeazans-c107.dts" "$UBOOT/dts/upstream/src/arm64/allwinner/"
cp "$HIER/jeazans_c107_fel_defconfig" "$UBOOT/configs/"
for P in "$HIER"/*.patch; do
	if git -C "$UBOOT" apply --check "$P" 2>/dev/null; then
		git -C "$UBOOT" apply "$P"
	fi
done

make -C "$UBOOT" O="$OUT" CROSS_COMPILE=aarch64-linux-gnu- jeazans_c107_fel_defconfig
if [ -n "$BL31_DATEI" ]; then
	make -C "$UBOOT" O="$OUT" CROSS_COMPILE=aarch64-linux-gnu- BL31="$BL31_DATEI" -j"$(nproc)"
else
	# Ohne BL31: CONFIG_SUNXI_BL31_BASE=0, U-Boot laeuft direkt in EL3 (reicht fuer FEL, Konsole, ums)
	make -C "$UBOOT" O="$OUT" CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)"
fi
"$OUT/tools/mkimage" -A arm64 -T script -C none -n "ums sichern" -d "$HIER/ums-sichern.txt" "$OUT/ums-sichern.scr" >/dev/null
ls -l "$OUT/u-boot-sunxi-with-spl.bin" "$OUT/ums-sichern.scr"
