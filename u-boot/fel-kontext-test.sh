#!/bin/bash
# Prueft, in welchem Kontext per FEL ausgefuehrter Code laeuft (haengt nicht):
# Miniprogramm bei 0x46000 schreibt CPSR, Lebenszeichen 0xAB, UART-LSR und SCTLR nach 0x46100
# und versucht nebenbei, '1' ueber UART0 zu senden (Teiler wird vorher gesetzt).
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
w() { sunxi-fel writel "$1" "$2"; }
sunxi-fel ver | cut -c1-40
w 0x0250000c 0x83; w 0x02500000 13; w 0x02500004 0; w 0x0250000c 0x03; w 0x02500008 0x07
echo "LSR per FEL-readl: $(sunxi-fel readl 0x02500014)"
sunxi-fel writel 0x46100 0 ; sunxi-fel writel 0x46104 0; sunxi-fel writel 0x46108 0; sunxi-fel writel 0x4610c 0
sunxi-fel write 0x46000 "$HIER/fel-tests/kontext-a32.bin"
sunxi-fel exe 0x46000
echo "CPSR         = $(sunxi-fel readl 0x46100)   (Modusbits 4:0: 13 SVC, 16 Monitor, 1a HYP, 1f System)"
echo "Lebenszeichen= $(sunxi-fel readl 0x46104)   (erwartet 0x000000ab)"
echo "UART-LSR     = $(sunxi-fel readl 0x46108)   (0x60 = UART erreichbar, 0 = Zugriff verworfen)"
echo "SCTLR        = $(sunxi-fel readl 0x4610c)   (Bit 12 I-Cache, Bit 2 D-Cache, Bit 0 MMU)"
echo "FEL danach: $(sunxi-fel ver | cut -c1-30)"
echo "== Cache-Probe: Befehl 'mov r3,#1' im Programm auf '3' aendern und erneut ausfuehren =="
sunxi-fel writel 0x46020 0xE3A03033
sunxi-fel writel 0x46104 0
sunxi-fel exe 0x46000
echo "Lebenszeichen= $(sunxi-fel readl 0x46104)   (Konsole: '3' = Code frisch gelesen, '1' = alter Cache-Inhalt)"
echo "FEL danach: $(sunxi-fel ver | cut -c1-30)"
