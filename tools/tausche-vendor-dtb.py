#!/usr/bin/env python3
"""Tauscht den Geraetebaum in einem vendor_boot-Abbild (VNDRBOOT v4); alles andere bleibt gleich.

Aufbau laut AOSP: Kopf (2128 Bytes), Hersteller-Ramdisk, DTB, Ramdisk-Tabelle, bootconfig,
jeder Teil auf die Seitengroesse aufgefuellt. Geaendert wird nur dtb_size im Kopf (Byte 2100).
Aufruf: tausche-vendor-dtb.py vendor_boot-alt.img neu.dtb vendor_boot-neu.img
"""
import struct
import sys

alt, dtb_datei, neu = sys.argv[1:4]
d = open(alt, "rb").read()
if d[:8] != b"VNDRBOOT" or struct.unpack("<I", d[8:12])[0] != 4:
	sys.exit("kein VNDRBOOT v4")
ps = struct.unpack("<I", d[12:16])[0]
ramdisk_groesse = struct.unpack("<I", d[24:28])[0]
kopf_groesse, dtb_groesse = struct.unpack("<II", d[2096:2104])
tabelle_groesse = struct.unpack("<I", d[2112:2116])[0]
bootconfig_groesse = struct.unpack("<I", d[2124:2128])[0]


def seiten(n):
	return (n + ps - 1) // ps * ps


def auffuellen(b):
	return b + b"\0" * ((-len(b)) % ps)


o = seiten(kopf_groesse)
ramdisk = d[o:o + ramdisk_groesse]
o += seiten(ramdisk_groesse) + seiten(dtb_groesse)
tabelle = d[o:o + tabelle_groesse]
o += seiten(tabelle_groesse)
bootconfig = d[o:o + bootconfig_groesse]
o += seiten(bootconfig_groesse)
if o != len(d):
	sys.exit(f"unerwartete Laenge: {len(d)} statt {o}")

dtb = open(dtb_datei, "rb").read()
kopf = bytearray(d[:kopf_groesse])
kopf[2100:2104] = struct.pack("<I", len(dtb))
bild = auffuellen(bytes(kopf)) + auffuellen(ramdisk) + auffuellen(dtb) + auffuellen(tabelle) + auffuellen(bootconfig)
open(neu, "wb").write(bild)
print(f"{neu}: {len(bild)} Bytes (DTB {dtb_groesse} -> {len(dtb)} Bytes, Seite {ps})")
