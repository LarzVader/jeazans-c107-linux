#!/usr/bin/env python3
"""Diagnose-Marken fuer den Rettungs-SPL: 'T' im 32-Bit-Vorspann (mit kompletter UART0-Einrichtung,
der BROM bereitet beim Kartenstart nichts vor), 'U' beim ersten AArch64-Befehl, 'V' am Anfang von board_init_f."""
import sys
boot0, start, board = sys.argv[1], sys.argv[2], sys.argv[3]
b = open(boot0).read()
alt = '\ttst     x0, x0                  // this is "b #0x84" in ARM\n\tb       reset\n\t.space  0x78\n'
assert b.count(alt) == 1
woerter = [
    0xE3010000, 0xE3400200, 0xE590190C, 0xE3811801, 0xE3811001, 0xE580190C, 0xE3A01000, 0xE5801524,  # CCU: UART0-Gate/Reset, APB1=HOSC
    0xE30000F0, 0xE3400200, 0xE5901000, 0xE3C1180F, 0xE3C11C0F, 0xE3811803, 0xE3811C03, 0xE5801000,  # PF2/PF4 -> Funktion 3
    0xE3000000, 0xE3400250, 0xE3A01083, 0xE580100C, 0xE3A0100D, 0xE5801000, 0xE3A01003, 0xE580100C,  # UART0: 8N1, Teiler 13
    0xE3A01054, 0xE5801000, 0xE3A01054, 0xE5801000,                                                  # 'T' 'T'
    0xEA000001,                                                                                      # b zum Original-Code bei 0x84
]
assert len(woerter) == 29
neu = ('\t.word\t0xea000000\t\t// Diagnose: ARM "b +8" zu den Marken, als AArch64 harmlos (ands x0, x0, x0)\n'
       '\tb       reset\n' + "".join(f'\t.word\t0x{w:08x}\n' for w in woerter) + '\t.space  4\n')
open(boot0, "w").write(b.replace(alt, neu))
s = open(start).read()
alt1 = "save_boot_params_ret:\n"
assert s.count(alt1) == 1
s = s.replace(alt1, alt1 + "\t/* Diagnose Jeazans C107: Marke 'U' an UART0-THR */\n\tldr\tx0, =0x02500000\n\tmov\tw1, #0x55\n\tstr\tw1, [x0]\n")
open(start, "w").write(s)
m = open(board).read()
alt2 = "void board_init_f(ulong dummy)\n{\n\tsunxi_sram_init();\n"
assert m.count(alt2) == 1
open(board, "w").write(m.replace(alt2, "void board_init_f(ulong dummy)\n{\n\twritel('V', 0x02500000);\t/* Diagnose: erster C-Befehl */\n\tsunxi_sram_init();\n"))
print("Marken eingetragen")
