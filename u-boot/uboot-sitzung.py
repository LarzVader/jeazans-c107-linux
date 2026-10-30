#!/usr/bin/env python3
"""Holt die Eingabeaufforderung des Hersteller-U-Boot ueber den SD-Slot und fuehrt Befehle aus.

Voraussetzung: env_b mit Autostart (seit 29.10.2026, bootcmd "run konsole;sleep 5;run linux";
"konsole" schaltet PF2/PF4 auf uart0 und gruesst). Dieses Programm wartet auf die Begruessung,
sendet Strg+C (bricht den Autostart im 5-s-Fenster ab) bis zur Eingabeaufforderung und dann die
Befehle. Alles Gelesene geht roh in die Logdatei, lesbare Zeilen nach stdout. Ohne Befehle endet
es am Prompt. pmOS von dort starten: Befehl "run linux".

Aufruf: uboot-sitzung.py logdatei [--am-prompt] [--warte SEKUNDEN] [befehl ...]
  --am-prompt  U-Boot steht schon am Prompt: nicht auf die Begruessung warten.
  --warte N    nach dem letzten Befehl noch N Sekunden mitlesen (z. B. beim Kernelstart).
Der Port darf nicht gleichzeitig von konsole-zeit.py oder picocom belegt sein.
"""
import os
import sys
import termios
import time

port = "/dev/ttyUSB0"
log = open(sys.argv[1], "ab")
befehle = sys.argv[2:]
am_prompt = "--am-prompt" in befehle
if am_prompt:
	befehle.remove("--am-prompt")
nachlauf = 0
if "--warte" in befehle:
	i = befehle.index("--warte")
	nachlauf = float(befehle[i + 1])
	del befehle[i:i + 2]

fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
termios.tcflush(fd, termios.TCIOFLUSH)


def antwort(max_dauer, ruhe=1.0):
	"""Liest, bis ruhe Sekunden nichts kommt oder max_dauer um ist."""
	daten = b""
	start = letzte = time.time()
	while time.time() - start < max_dauer:
		try:
			d = os.read(fd, 4096)
		except BlockingIOError:
			d = b""
		if d:
			daten += d
			log.write(d)
			log.flush()
			letzte = time.time()
		elif time.time() - letzte > ruhe:
			break
		else:
			time.sleep(0.02)
	return daten


def zeigen(daten):
	text = daten.decode("ascii", errors="replace").replace("\r", "")
	for zeile in text.split("\n"):
		if zeile.strip() and sum(c.isprintable() for c in zeile) > 0.8 * len(zeile):
			print(zeile, flush=True)


if am_prompt:
	os.write(fd, b"\r")
	zeigen(antwort(2.0))
else:
	print(time.strftime("%H:%M:%S"), "warte bis 180 s auf die U-Boot-Begruessung ...", flush=True)
	puffer = b""
	ende = time.time() + 180
	while time.time() < ende and b"U-Boot-Konsole am SD-Slot" not in puffer:
		puffer += antwort(0.3, ruhe=0.3)
	zeigen(puffer)
	if b"U-Boot-Konsole am SD-Slot" not in puffer:
		sys.exit("Keine Begruessung gesehen.")

	print(time.strftime("%H:%M:%S"), "Begruessung da, sende Strg+C ...", flush=True)
	puffer = b""
	for _ in range(50):
		os.write(fd, b"\x03")
		puffer += antwort(0.1, ruhe=0.1)
	os.write(fd, b"\r")
	puffer += antwort(2.0)
	zeigen(puffer)
	if b"Starting kernel" in puffer or b"boot_normal" in puffer.split(b"\x03")[-1]:
		print("Achtung: der Kernel startet womoeglich schon.", flush=True)

for befehl in befehle:
	print(f"\n{time.strftime('%H:%M:%S')} >>> {befehl}", flush=True)
	os.write(fd, befehl.encode() + b"\r")
	zeigen(antwort(30.0, ruhe=1.5))
if nachlauf:
	print(f"\n{time.strftime('%H:%M:%S')} lese noch {nachlauf:.0f} s mit ...", flush=True)
	zeigen(antwort(nachlauf, ruhe=nachlauf))
os.close(fd)
