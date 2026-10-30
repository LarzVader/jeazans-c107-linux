#!/bin/bash
# Eingrenzung: welcher Registerzugriff macht die UART fuer per FEL ausgefuehrten Code erreichbar?
# Erwartet frischen FEL-Modus. Schreibt vor jedem Schritt eine andere Ziffer per Miniprogramm.
set -uo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
r() { sunxi-fel readl "$1"; }
w() { sunxi-fel writel "$1" "$2"; }
blob() {  # $1 = Ziffer
	w 0x46020 "0xE3A0303$1"; w 0x46104 0; sunxi-fel exe 0x46000
	echo "Schritt $1: Lebenszeichen $(r 0x46104), LSR $(r 0x46108)"
}
sunxi-fel ver | cut -c1-40
echo "== Register vor jedem Eingriff =="
for a in 0x02001524:APB1 0x02001520:APB0 0x0200190c:UART_BGR 0x020000f0:PF_CFG0 0x02000114:PF_PULL0 0x020000f4:PF_CFG1 0x02000104:PF_DRV0 0x0250000c:LCR 0x0250007c:USR 0x02500014:LSR 0x02500004:IER 0x02500010:MCR; do printf '%-9s %s = %s\n' "${a#*:}" "${a%:*}" "$(r ${a%:*})"; done
w 0x0250000c 0x83; echo "DLL = $(r 0x02500000), DLH = $(r 0x02500004) (vor Aenderung)"
w 0x02500000 13; w 0x02500004 0; w 0x0250000c 0x03; w 0x02500008 0x07
sunxi-fel write 0x46000 "$HIER/fel-tests/kontext-a32.bin"
blob 5
cfg=$(r 0x020000f0); w 0x020000f0 "$(printf '0x%08x' $(( (cfg & ~0x000f0f00) | 0x00030300 )))"; echo "PF_CFG0 geschrieben: $(r 0x020000f0)"
blob 6
bgr=$(r 0x0200190c); w 0x0200190c "$(printf '0x%08x' $(( bgr | 0x10001 )))"; echo "UART_BGR geschrieben: $(r 0x0200190c)"
blob 7
w 0x02001524 0; echo "APB1 geschrieben"
blob 8
pull=$(r 0x02000114); w 0x02000114 "$(printf '0x%08x' $(( (pull & ~0x300) | 0x100 )))"; echo "PF_PULL0 geschrieben: $(r 0x02000114)"
blob 9
echo "FEL danach: $(sunxi-fel ver | cut -c1-30)"
