#!/usr/bin/env python3
"""Aendert Variablen in einer gesicherten U-Boot-Umgebung (env_a) des Jeazans C107 und
berechnet die Pruefsumme neu.

Format (Hersteller-U-Boot 2018.07, SUNXI_FLASH): CRC32 in Byte 0-3, danach ab Byte 4
"name=wert\\0"-Eintraege bis "\\0\\0", Umgebung 0x20000 Bytes, Partition 256 KiB
(der Rest der Partition wird aus dem Original uebernommen).

Aufruf: baue-env.py original.img ausgabe.img name=wert [name=wert ...]
        Ein leerer Wert ("name=") loescht die Variable.
"""
import struct
import sys
import zlib

ENV_SIZE = 0x20000

quelle, ziel, *aenderungen = sys.argv[1:]
roh = open(quelle, "rb").read()
crc = struct.unpack_from("<I", roh, 0)[0]
if zlib.crc32(roh[4:ENV_SIZE]) & 0xFFFFFFFF != crc:
	sys.exit(f"{quelle}: Pruefsumme stimmt nicht, kein gueltiges Original")

eintraege = [e.decode() for e in roh[4:ENV_SIZE].split(b"\0\0")[0].split(b"\0") if e]
werte = dict(e.split("=", 1) for e in eintraege)
reihenfolge = [e.split("=", 1)[0] for e in eintraege]
for a in aenderungen:
	name, wert = a.split("=", 1)
	if wert:
		if name not in werte:
			reihenfolge.append(name)
		werte[name] = wert
	else:
		werte.pop(name, None)
		reihenfolge = [n for n in reihenfolge if n != name]

daten = b"".join(f"{n}={werte[n]}".encode() + b"\0" for n in reihenfolge) + b"\0"
if len(daten) > ENV_SIZE - 4:
	sys.exit("Umgebung zu gross")
daten += b"\0" * (ENV_SIZE - 4 - len(daten))
neu = struct.pack("<I", zlib.crc32(daten) & 0xFFFFFFFF) + daten + roh[ENV_SIZE:]
open(ziel, "wb").write(neu)
print(f"{ziel}: {len(neu)} Bytes, {len(reihenfolge)} Variablen, CRC {zlib.crc32(daten) & 0xFFFFFFFF:#010x}")
for a in aenderungen:
	name = a.split("=", 1)[0]
	print(f"  {name} = {werte.get(name, '(geloescht)')}")
