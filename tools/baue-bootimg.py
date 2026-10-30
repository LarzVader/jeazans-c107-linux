#!/usr/bin/env python3
"""Baut ein Android-Boot-Image (Header-Version 2) aus Kernel, Initramfs und Geraetebaum.

Version 2 ist die letzte, die den Geraetebaum direkt im Image traegt; damit laesst
sich per "fastboot boot" ohne Flashen testen, ob der Hersteller-Bootloader unseren
Kernel mit unserem Geraetebaum startet. Entspricht dem Format von AOSP mkbootimg.

Aufruf: baue-bootimg.py --kernel Image --ramdisk initramfs --dtb c107.dtb \
            --cmdline "..." --out boot.img [--page-size 4096] [--base 0x40000000]
"""
import argparse
import hashlib
import struct

p = argparse.ArgumentParser()
p.add_argument("--kernel", required=True)
p.add_argument("--ramdisk", required=True)
p.add_argument("--dtb", required=True)
p.add_argument("--cmdline", default="")
p.add_argument("--out", required=True)
p.add_argument("--page-size", type=int, default=4096)
p.add_argument("--base", type=lambda s: int(s, 0), default=0x40000000)
p.add_argument("--kernel-offset", type=lambda s: int(s, 0), default=0x00080000)
p.add_argument("--ramdisk-offset", type=lambda s: int(s, 0), default=0x04000000)
p.add_argument("--tags-offset", type=lambda s: int(s, 0), default=0x00000100)
p.add_argument("--dtb-offset", type=lambda s: int(s, 0), default=0x05000000)   # hinter Kernel (54 MB ab 0x80000) und Ramdisk (ab 0x4000000)
p.add_argument("--name", default="pmOS-c107")
a = p.parse_args()

kernel = open(a.kernel, "rb").read()
ramdisk = open(a.ramdisk, "rb").read()
dtb = open(a.dtb, "rb").read()
cmdline = a.cmdline.encode()
if len(cmdline) > 512 + 1024:
	raise SystemExit("Kommandozeile zu lang")
ps = a.page_size

def seite(blob):
	rest = (-len(blob)) % ps
	return blob + b"\0" * rest

sha = hashlib.sha1()
for blob in (kernel, ramdisk, b"", dtb):      # Kernel, Ramdisk, second (leer), DTB
	sha.update(blob)
	sha.update(struct.pack("<I", len(blob)))
ident = sha.digest() + b"\0" * 12

header = struct.pack(
	"<8s10I16s512s32s1024sIQIIQ",
	b"ANDROID!",
	len(kernel), a.base + a.kernel_offset,
	len(ramdisk), a.base + a.ramdisk_offset,
	0, 0,                                    # second stage: Groesse, Adresse
	a.base + a.tags_offset,
	ps,
	2,                                       # header_version
	0,                                       # os_version
	a.name.encode()[:16],
	cmdline[:512],
	ident,
	cmdline[512:512 + 1024],
	0, 0,                                    # recovery_dtbo: Groesse, Offset
	1660,                                    # header_size (Version 2)
	len(dtb), a.base + a.dtb_offset,
)
assert len(header) == 1660, len(header)
image = seite(header) + seite(kernel) + seite(ramdisk) + seite(dtb)
open(a.out, "wb").write(image)
print(f"{a.out}: {len(image)} Bytes (Kernel {len(kernel)}, Ramdisk {len(ramdisk)}, DTB {len(dtb)}, Seite {ps})")
