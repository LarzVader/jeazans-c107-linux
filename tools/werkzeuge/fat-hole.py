#!/usr/bin/env python3
"""Holt eine Datei aus dem Wurzelverzeichnis eines FAT12/16/32-Abbilds (nur 8.3-Namen).
Aufruf: fat-hole.py abbild NAME.EXT ziel   (ohne NAME: Wurzelverzeichnis auflisten)"""
import struct
import sys

d = open(sys.argv[1], "rb").read()
bps, spc, res, nfat = struct.unpack_from("<HBHB", d, 11)
nroot, tot16, _, fsz16 = struct.unpack_from("<HHBH", d, 17)
tot32, fsz32 = struct.unpack_from("<I", d, 32)[0], struct.unpack_from("<I", d, 36)[0]
fsz = fsz16 or fsz32
tot = tot16 or tot32
rootsek = (nroot * 32 + bps - 1) // bps
daten = res + nfat * fsz + rootsek
cl_anz = (tot - daten) // spc
typ = 12 if cl_anz < 4085 else 16 if cl_anz < 65525 else 32
fat = d[res * bps:(res + fsz) * bps]
clb = spc * bps


def naechster(c):
	if typ == 12:
		v = struct.unpack_from("<H", fat, c + c // 2)[0]
		return v >> 4 if c & 1 else v & 0xFFF
	if typ == 16:
		return struct.unpack_from("<H", fat, c * 2)[0]
	return struct.unpack_from("<I", fat, c * 4)[0] & 0x0FFFFFFF


def kette(c):
	ende = {12: 0xFF8, 16: 0xFFF8, 32: 0x0FFFFFF8}[typ]
	while 2 <= c < ende:
		yield d[(daten + (c - 2) * spc) * bps:][:clb]
		c = naechster(c)


if typ == 32:
	wurzel = b"".join(kette(struct.unpack_from("<I", d, 44)[0]))
else:
	wurzel = d[(res + nfat * fsz) * bps:][:rootsek * bps]
print("FAT%d, %d Cluster zu %d Bytes" % (typ, cl_anz, clb))
for i in range(0, len(wurzel), 32):
	e = wurzel[i:i + 32]
	if e[0] == 0:
		break
	if e[0] == 0xE5 or e[11] == 0x0F or e[11] & 0x08:
		continue
	name = (e[:8].decode("latin1").rstrip() + "." + e[8:11].decode("latin1").rstrip()).rstrip(".")
	start = struct.unpack_from("<H", e, 26)[0] | (struct.unpack_from("<H", e, 20)[0] << 16)
	groesse = struct.unpack_from("<I", e, 28)[0]
	if len(sys.argv) < 3:
		print("%-12s %9d" % (name, groesse))
	elif name.upper() == sys.argv[2].upper():
		open(sys.argv[3], "wb").write(b"".join(kette(start))[:groesse])
		print("geschrieben:", sys.argv[3], groesse, "Bytes")
		break
