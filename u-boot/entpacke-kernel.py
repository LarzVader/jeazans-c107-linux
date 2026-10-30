#!/usr/bin/env python3
"""Loest den gzip-gepackten Kernel aus dem EFI-zboot-Paket (vmlinuz) heraus.

postmarketOS installiert fuer arm64 nicht das rohe Kernelabbild, sondern
vmlinuz.efi: ein PE-Programm, das den gepackten Kernel als Nutzlast traegt
und ihn nur beim Start ueber EFI entpackt. U-Boots booti kann die Nutzlast
(Image.gz) dagegen direkt starten.

Aufruf: entpacke-kernel.py vmlinuz Image.gz
"""
import struct
import sys

quelle, ziel = sys.argv[1], sys.argv[2]
daten = open(quelle, "rb").read()
if daten[4:8] != b"zimg":
	sys.exit(f"{quelle}: kein EFI-zboot-Paket (Magie 'zimg' fehlt)")
nutzlast_ab, nutzlast_groesse = struct.unpack_from("<II", daten, 8)
kompression = daten[0x18:0x38].rstrip(b"\0").decode()
if kompression != "gzip":
	sys.exit(f"{quelle}: Kompression {kompression!r}, erwartet gzip")
nutzlast = daten[nutzlast_ab:nutzlast_ab + nutzlast_groesse]
if nutzlast[:2] != b"\x1f\x8b":
	sys.exit(f"{quelle}: Nutzlast beginnt nicht mit der gzip-Magie")
open(ziel, "wb").write(nutzlast)
print(f"{ziel}: {len(nutzlast)} Bytes gzip-gepackter Kernel aus {quelle}")
