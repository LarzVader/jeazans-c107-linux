#!/usr/bin/env python3
"""Liest die Register der laufenden Anzeigekette, nur lesend. Laeuft auf dem Tablet als root.
Nur Bloecke, deren Takte simpledrm an haelt, ungetaktete koennten den Bus aufhaengen (dann greift
der Watchdog). Bereiche wie im Dump des Trimui-Projekts, dort mit laufender Anzeige ohne Probleme.
Ergebnis: /tmp/display-dump.txt, je Zeile "0xADRESSE = 0xWERT".
Aufruf: sudo python3 /home/user/werkzeuge/display-register-lesen.py"""
import ctypes
import mmap
import os

BLOECKE = [
    ("DE-TOP", 0x05008000, 128),
    ("MIXER-GLB", 0x05100000, 16),
    ("OVL phy0/VI0", 0x05101000, 64),
    # phy2 bis phy5 fehlen mit Absicht: das Lesen von 0x05141000 haengt den Bus auf (am
    # U-Boot-Prompt gesehen, zurueck nur per 6 s Ein/Aus). Aktiv ist phy6.
    ("OVL phy1", 0x05121000, 16),
    ("OVL phy6", 0x051c1000, 36),
    ("VSU phy0", 0x05104000, 56),
    ("BLENDER", 0x05281000, 64),
    ("FMT", 0x05285000, 16),
    ("DCSC", 0x0528b000, 32),
    ("TCON-TOP", 0x05500000, 24),
    ("TCON-LCD1", 0x05502000, 96),
    ("DSI1", 0x05508000, 192),
    ("COMBO-PHY1", 0x05509000, 80),
    ("CCU DE", 0x02001600, 1),
    ("CCU Display", 0x02001b00, 64),
    ("PWM0", 0x02000c00, 64),
    ("PWM0 Kanal 0", 0x02000d00, 4),
]
SEITE = mmap.PAGESIZE
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
with open("/tmp/display-dump.txt", "w") as aus:
    for name, adr, worte in BLOECKE:
        aus.write(f"## === {name} {adr:#x} ===\n")
        aus.flush()
        basis = adr & ~(SEITE - 1)
        laenge = (adr - basis + worte * 4 + SEITE - 1) & ~(SEITE - 1)
        mm = mmap.mmap(fd, laenge, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=basis)
        anfang = ctypes.addressof(ctypes.c_char.from_buffer(mm))
        for i in range(worte):
            a = adr + i * 4
            w = ctypes.c_uint32.from_address(anfang + (a - basis)).value
            aus.write(f"{a:#010x} = {w:#010x}\n")
        aus.flush()
os.chmod("/tmp/display-dump.txt", 0o644)
print("fertig: /tmp/display-dump.txt")
