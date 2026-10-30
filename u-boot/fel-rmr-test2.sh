#!/bin/bash
# Teil 1 (haengt nur, wenn der Code nicht-sicher laeuft): Miniprogramm liest RMR und SCR,
#   das geht nur in der sicheren Welt (EL3). Lebenszeichen 0xAB, '1' vor und '2' nach den Lesungen.
# Teil 2 (haengt immer): 64-Bit-Programm per RMR-Warmstart, sendet 'Z'.
# Vorher: PF2/PF4 auf UART0 und Teiler 13 setzen.
set -uo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
r() { sunxi-fel readl "$1"; }
w() { sunxi-fel writel "$1" "$2"; }
sunxi-fel ver | cut -c1-40
cfg=$(r 0x020000f0); w 0x020000f0 "$(printf '0x%08x' $(( (cfg & ~0x000f0f00) | 0x00030300 )))"
w 0x0250000c 0x83; w 0x02500000 13; w 0x02500004 0; w 0x0250000c 0x03; w 0x02500008 0x07
echo "PF_CFG0 = $(r 0x020000f0)"
echo "== Teil 1: RMR und SCR lesen =="
for a in 0x46104 0x46110 0x46114; do w $a 0; done
sunxi-fel write 0x46000 "$HIER/fel-tests/kontext2-a32.bin"
sunxi-fel exe 0x46000
echo "Lebenszeichen $(r 0x46104)   RMR $(r 0x46110)   SCR $(r 0x46114)   (SCR Bit 0 = NS)"
echo "FEL danach: $(sunxi-fel ver 2>&1 | cut -c1-30)"
echo "== Teil 2: RMR-Warmstart mit 64-Bit-Programm (erwartet 'Z') =="
sunxi-fel write 0x47000 "$HIER/fel-tests/uart-a64-Z.bin"
sunxi-fel reset64 0x47000
echo "reset64 abgesetzt"
