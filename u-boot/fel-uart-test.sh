#!/bin/bash
# UART0-Test direkt aus dem FEL-Modus, ohne SPL: stellt per sunxi-fel Takt, Pins und
# Teiler ein und sendet Text ueber UART0 (PF2/PF4, microSD-Slot). Haengt nicht und
# laesst sich beliebig oft wiederholen, solange das Tablet im FEL-Modus ist.
# Aufruf: ./fel-uart-test.sh [Teiler] [Text]
#   Teiler 13 = 24 MHz / (16 * 115200). Bei anderem UART-Takt: 4 (8 MHz), 54 (100 MHz).
# Mitlesen: python3 konsole-zeit.py (oder ./konsole.sh) auf dem CP2102.
set -euo pipefail
DIV="${1:-13}"
TEXT="${2:-Jeazans C107 FEL-UART-Test}"

r() { sunxi-fel readl "$1"; }
w() { sunxi-fel writel "$1" "$2"; }
hex() { printf '0x%08x' "$1"; }

CCU=0x02001000; PIO=0x02000000; UART=0x02500000; GICD=0x03400000
APB1=$(( CCU + 0x524 )); APB0=$(( CCU + 0x520 )); UART_BGR=$(( CCU + 0x90c )); PLL_PERI0=$(( CCU + 0x20 ))
PF_CFG0=$(( PIO + 5 * 0x30 )); PF_PULL0=$(( PF_CFG0 + 0x24 ))
POW_MOD_SEL=$(( PIO + 0x340 )); POW_MOD_VAL=$(( PIO + 0x348 ))
THR=$(( UART + 0x00 )); DLH=$(( UART + 0x04 )); FCR=$(( UART + 0x08 )); LCR=$(( UART + 0x0c )); LSR=$(( UART + 0x14 )); USR=$(( UART + 0x7c ))

sunxi-fel ver
echo "== Register vorher =="
for n in APB0 APB1 UART_BGR PLL_PERI0 PF_CFG0 PF_PULL0 POW_MOD_SEL POW_MOD_VAL; do
	printf '%-12s %s = %s\n' "$n" "$(hex ${!n})" "$(r $(hex ${!n}))"
done
printf '%-12s %s = %s  (Bits 31:24 ProductID: 02 GIC-600, 00 GIC-500, 04 GIC-700)\n' GICD_IIDR "$(hex $((GICD + 4)))" "$(r $(hex $((GICD + 4))))"
printf '%-12s %s = %s\n' GICD_TYPER "$(hex $((GICD + 8)))" "$(r $(hex $((GICD + 8))))"
printf '%-12s %s = %s\n' UART_LCR "$(hex $LCR)" "$(r $(hex $LCR))"
printf '%-12s %s = %s\n' UART_USR "$(hex $USR)" "$(r $(hex $USR))"

echo "== UART0 einrichten (Teiler $DIV) =="
w "$(hex $APB1)" 0x00000000                                   # APB1 = HOSC 24 MHz / 1
bgr=$(r "$(hex $UART_BGR)"); w "$(hex $UART_BGR)" "$(hex $(( bgr | 0x10001 )))"   # Gate + Reset-Freigabe UART0
cfg=$(r "$(hex $PF_CFG0)"); w "$(hex $PF_CFG0)" "$(hex $(( (cfg & ~0x000f0f00) | 0x00030300 )))"  # PF2, PF4 -> Funktion 3
pull=$(r "$(hex $PF_PULL0)"); w "$(hex $PF_PULL0)" "$(hex $(( (pull & ~0x300) | 0x100 )))"        # PF4 Pull-up
w "$(hex $LCR)" 0x83          # DLAB an, 8N1
w "$(hex $THR)" "$DIV"        # DLL
w "$(hex $DLH)" 0x0           # DLH
w "$(hex $LCR)" 0x03          # DLAB aus
w "$(hex $FCR)" 0x07          # FIFO an und leeren
printf 'LCR jetzt %s, LSR %s\n' "$(r "$(hex $LCR)")" "$(r "$(hex $LSR)")"

echo "== sende: '$TEXT DIV=$DIV' =="
for c in $(printf '\r\n%s DIV=%s\r\n' "$TEXT" "$DIV" | od -An -tu1); do
	w "$(hex $THR)" "$c"
done
echo "fertig"
