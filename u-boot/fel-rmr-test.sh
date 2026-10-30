#!/bin/bash
# Prueft den Einstieg in den 64-Bit-Modus, den U-Boots SPL-Vorspann braucht, ohne U-Boot:
#  1. RVBAR-Register (0x08000040) lesen, beschreiben, zuruecklesen: ist es beschreibbar?
#  2. SRAM_VER_REG (0x03000024) lesen, das liest der SPL-Vorspann ebenfalls.
#  3. 32-Bit-Programm per FEL ausfuehren: sendet '1' ueber UART0 und kehrt zurueck.
#  4. 64-Bit-Programm per RMR-Warmstart (sunxi-fel reset64): sendet '2', bleibt dann in wfi.
# Nach Schritt 4 ist FEL tot, das Tablet muss aus- und eingeschaltet werden.
# Mitlesen: python3 konsole-zeit.py auf dem CP2102.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
A32="$HIER/fel-tests/uart-a32.bin"
A64="$HIER/fel-tests/uart-a64.bin"
ADDR32=0x45000
ADDR64=0x45100

sunxi-fel ver
echo "== 1. RVBAR 0x08000040 =="
echo "vorher:      $(sunxi-fel readl 0x08000040)"
sunxi-fel writel 0x08000040 "$ADDR64"
echo "nach write:  $(sunxi-fel readl 0x08000040)  (erwartet $ADDR64, sonst nicht beschreibbar)"
echo "== 2. SRAM_VER_REG 0x03000024 == $(sunxi-fel readl 0x03000024)"
echo "== 3. 32-Bit-Programm ausfuehren (erwartet '1' an der Konsole) =="
sunxi-fel write "$ADDR32" "$A32"
sunxi-fel exe "$ADDR32"
echo "FEL danach: $(sunxi-fel ver | cut -c1-30)"
echo "== 4. 64-Bit-Programm per RMR-Warmstart (erwartet '2', danach haengt FEL) =="
sunxi-fel write "$ADDR64" "$A64"
sunxi-fel reset64 "$ADDR64"
echo "reset64 abgesetzt"
