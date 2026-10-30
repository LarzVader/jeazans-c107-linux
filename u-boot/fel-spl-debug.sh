#!/bin/bash
# Diagnose-Lauf: erst UART0 per FEL fertig einrichten (der BROM laesst den Baudraten-
# Teiler auf 0, dann sendet die UART nichts), dann das 32-Bit-Miniprogramm ('1' als
# Lebenszeichen), dann den Diagnose-SPL aus build-debug/ starten. Seine Marken
# S, L, 0, A, B, ... zeigen, wie weit er kommt. Danach ist FEL meist tot.
# Mitlesen: python3 konsole-zeit.py auf dem CP2102.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
BIN="${UBOOT_BIN:-$HIER/build-debug/u-boot-sunxi-with-spl.bin}"
UART=0x02500000
w() { sunxi-fel writel "$1" "$2"; }

sunxi-fel ver | cut -c1-40
echo "== UART0: Teiler 13 (115200 bei 24 MHz) =="
w 0x0250000c 0x83     # DLAB an
w 0x02500000 13       # DLL
w 0x02500004 0        # DLH
w 0x0250000c 0x03     # 8N1, DLAB aus
w 0x02500008 0x07     # FIFO an und leeren
echo "== Lebenszeichen: 32-Bit-Programm, erwartet '1' =="
sunxi-fel write 0x45000 "$HIER/fel-tests/uart-a32.bin"
sunxi-fel exe 0x45000
echo "FEL danach: $(sunxi-fel ver | cut -c1-30)"
echo "== Diagnose-SPL: $BIN =="
sunxi-fel -v -p uboot "$BIN" 2>&1 | tr '\r' '\n' | grep -v '^\s*$' | tail -n 4 || true
echo "fertig"
