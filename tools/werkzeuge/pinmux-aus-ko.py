#!/usr/bin/env python3
"""Liest die Pin-Funktionstabelle (SUNXI_PIN/SUNXI_FUNCTION) aus einem Allwinner-BSP-Pinctrl-Modul.
Aufruf: pinmux-aus-ko.py modul.ko PH0 PH1 ...   (ohne Pins: alle Pins von Bank H)"""
import struct
import sys

d = open(sys.argv[1], "rb").read()
shoff, = struct.unpack_from("<Q", d, 0x28)
shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x3A)
sek = []
for i in range(shnum):
	n, typ, flags, addr, off, size, link, info, align, entsize = struct.unpack_from("<IIQQQQIIQQ", d, shoff + i * shentsize)
	sek.append(dict(n=n, typ=typ, off=off, size=size, link=link, info=info, entsize=entsize))
namen = sek[shstrndx]
for s in sek:
	e = d.find(b"\0", namen["off"] + s["n"])
	s["name"] = d[namen["off"] + s["n"]:e].decode()

symtab = next(s for s in sek if s["typ"] == 2)
syms = []
for i in range(symtab["size"] // 24):
	st_name, st_info, st_other, st_shndx, st_value, st_size = struct.unpack_from("<IBBHQQ", d, symtab["off"] + i * 24)
	syms.append((st_shndx, st_value))

# Zeiger: (Sektion, Offset) -> (Zielsektion, Zieloffset)
zeiger = {}
for s in sek:
	if s["typ"] != 4:  # SHT_RELA
		continue
	ziel = s["info"]
	for i in range(s["size"] // 24):
		r_off, r_info, r_add = struct.unpack_from("<QQq", d, s["off"] + i * 24)
		if r_info & 0xFFFFFFFF != 257:  # R_AARCH64_ABS64
			continue
		shndx, wert = syms[r_info >> 32]
		if 0 < shndx < len(sek):
			zeiger[(ziel, r_off)] = (shndx, wert + r_add)


def text(z):
	s = sek[z[0]]
	a = s["off"] + z[1]
	return d[a:d.find(b"\0", a)].decode("latin1")


def bytes_an(sx, off, n):
	return d[sek[sx]["off"] + off:sek[sx]["off"] + off + n]


gesucht = set(sys.argv[2:])
for (sx, off), z in sorted(zeiger.items()):
	name = text(z)
	if not (name in gesucht or (not gesucht and name.startswith("PH") and name[2:].isdigit())):
		continue
	# sunxi_desc_pin: pin {number, name, drv_data} + variant + functions
	nummer, = struct.unpack("<I", bytes_an(sx, off - 8, 4))
	fz = zeiger.get((sx, off + 24))
	if not fz:
		print(name, "ohne Funktionszeiger")
		continue
	funktionen = []
	f = fz[1]
	while (fz[0], f + 8) in zeiger:
		fname = text(zeiger[(fz[0], f + 8)])
		mux = bytes_an(fz[0], f + 16, 1)[0]
		funktionen.append("%d=%s" % (mux, fname))
		f += 24
	print("%-5s (Nr. %3d): %s" % (name, nummer, ", ".join(funktionen)))
