#!/usr/bin/env python3
"""Baut die Android-Boot-Images (Header-Version 4) fuer den Hersteller-Bootloader des
Jeazans C107, nach dem Muster der gesicherten Originale:

  boot.img         Kernel allein, cmdline (Seite 4096)
  vendor_boot.img  VNDRBOOT v4: unsere Initramfs als Hersteller-Ramdisk, unser DTB,
                   cmdline, Ramdisk-Tabelle, bootconfig aus dem Original (Seite 2048)
  init_boot.img    v4 mit leerer Ramdisk (sonst ueberschreibt Androids /init unseres)
  dtbo-leer.img    DTBO-Tabelle ohne Eintraege

Aufruf: baue-android-images.py --kernel Image --ramdisk initramfs --dtb c107.dtb
            --cmdline "..." --vendor-boot-original vendor_boot_a.img --out-dir fastboot/
"""
import argparse
import gzip
import os
import struct

p = argparse.ArgumentParser()
p.add_argument("--kernel", required=True)
p.add_argument("--ramdisk", required=True)
p.add_argument("--dtb", required=True)
p.add_argument("--cmdline", default="")
p.add_argument("--vendor-boot-original", required=True, help="gesichertes vendor_boot_a.img (fuer bootconfig und Adressen)")
p.add_argument("--out-dir", required=True)
p.add_argument("--suffix", default="pmos")
# Unser Kernel ist 54 MB gross (Original 47 MB) und ragt ab 0x40080000 bis 0x436a0000;
# die Original-Adressen fuer DTB (0x43300000) und Ramdisk (0x43400000) laegen mitten darin.
p.add_argument("--dtb-addr", type=lambda s: int(s, 0), default=0x45000000)
p.add_argument("--ramdisk-addr", type=lambda s: int(s, 0), default=0x45100000)
a = p.parse_args()


def seite(blob, ps):
	return blob + b"\0" * ((-len(blob)) % ps)


# --- Original-vendor_boot auslesen: Adressen, cmdline und bootconfig uebernehmen ---
vo = open(a.vendor_boot_original, "rb").read()
assert vo[:8] == b"VNDRBOOT", "kein VNDRBOOT-Image"
(hv, ps, kernel_addr, ramdisk_addr, vrd_size) = struct.unpack_from("<5I", vo, 8)
vo_cmdline = vo[28:28 + 2048].split(b"\0")[0]
tags_addr = struct.unpack_from("<I", vo, 2076)[0]
name = vo[2080:2096].split(b"\0")[0]
(hdr_size, dtb_size, dtb_addr) = struct.unpack_from("<IIQ", vo, 2096)
(tab_size, tab_num, tab_entry_size, bc_size) = struct.unpack_from("<4I", vo, 2112)
assert hv == 4 and tab_entry_size == 108
o = (-(-hdr_size // ps)) * ps                      # Header belegt ganze Seiten
o_ramdisk = o
o_dtb = o_ramdisk + (-(-vrd_size // ps)) * ps
o_tab = o_dtb + (-(-dtb_size // ps)) * ps
o_bc = o_tab + (-(-tab_size // ps)) * ps
bootconfig = vo[o_bc:o_bc + bc_size]
vendor_dtb = vo[o_dtb:o_dtb + dtb_size]
print(f"Original vendor_boot: Seite {ps}, kernel_addr {kernel_addr:#x}, ramdisk_addr {ramdisk_addr:#x}, "
      f"dtb_addr {dtb_addr:#x}, tags {tags_addr:#x}, name {name!r}, bootconfig {bc_size} Bytes, cmdline {vo_cmdline!r}")
os.makedirs(a.out_dir, exist_ok=True)
open(os.path.join(a.out_dir, "vendor_boot-original.dtb"), "wb").write(vendor_dtb)

kernel = open(a.kernel, "rb").read()
ramdisk = open(a.ramdisk, "rb").read()
dtb = open(a.dtb, "rb").read()
cmdline = a.cmdline.encode()

# --- boot.img v4: Kernel allein, Seite 4096 ---
BPS = 4096
hdr = struct.pack("<8s4I4I I 1536s I", b"ANDROID!", len(kernel), 0, 0, 1584, 0, 0, 0, 0, 4, cmdline[:1536], 0)
assert len(hdr) == 1584
boot = seite(hdr, BPS) + seite(kernel, BPS)
pfad = os.path.join(a.out_dir, f"boot-{a.suffix}.img")
open(pfad, "wb").write(boot)
print(f"{pfad}: {len(boot)} Bytes (Kernel {len(kernel)})")

# --- vendor_boot.img v4 ---
tab_entry = struct.pack("<3I32s16I", len(ramdisk), 0, 1, b"pmos", *([0] * 16))   # Typ 1 = PLATFORM
assert len(tab_entry) == 108
# cmdline des Herstellers bleibt in vendor_boot (endet mit "bootconfig"), unsere steht in boot.img
vhdr = struct.pack("<8s5I2048sI16sIIQ4I", b"VNDRBOOT", 4, ps, kernel_addr, a.ramdisk_addr, len(ramdisk),
                   vo_cmdline[:2048], tags_addr, name, 2128, len(dtb), a.dtb_addr,
                   108, 1, 108, len(bootconfig))
assert len(vhdr) == 2128
vendor = seite(vhdr, ps) + seite(ramdisk, ps) + seite(dtb, ps) + seite(tab_entry, ps) + seite(bootconfig, ps)
pfad = os.path.join(a.out_dir, f"vendor_boot-{a.suffix}.img")
open(pfad, "wb").write(vendor)
print(f"{pfad}: {len(vendor)} Bytes (Ramdisk {len(ramdisk)}, DTB {len(dtb)}, bootconfig {len(bootconfig)})")

# --- init_boot.img v4 mit leerer Ramdisk (nur TRAILER!!!, gzip) ---
trailer = b"070701" + b"00000000" * 11 + b"0000000b" + b"00000000" + b"TRAILER!!!\0"
leer = gzip.compress(trailer + b"\0" * ((-len(trailer)) % 4), compresslevel=9)
ihdr = struct.pack("<8s4I4I I 1536s I", b"ANDROID!", 0, len(leer), 0, 1584, 0, 0, 0, 0, 4, b"", 0)
init_boot = seite(ihdr, BPS) + seite(leer, BPS)
pfad = os.path.join(a.out_dir, "init_boot-leer.img")
open(pfad, "wb").write(init_boot)
print(f"{pfad}: {len(init_boot)} Bytes (leere Ramdisk {len(leer)} Bytes)")

# --- dtbo ohne Eintraege ---
dtbo = struct.pack(">8I", 0xd7b7ab1e, 32, 32, 32, 0, 32, ps, 0)
pfad = os.path.join(a.out_dir, "dtbo-leer.img")
open(pfad, "wb").write(dtbo)
print(f"{pfad}: {len(dtbo)} Bytes")
