#!/usr/bin/env python3
"""Misst einen Neustart-Versuch an der seriellen Konsole.

Liest /dev/ttyUSB0 roh in eine Logdatei mit, zeigt die wichtigen Zeilen mit Uhrzeit und
endet einige Sekunden nach der U-Boot-Begruessung (env_b, "run konsole"). Ausgegeben wird,
wie viele Sekunden zwischen der letzten Kernel-Meldung zum Neustart ("Restarting system",
"sysrq: Resetting" ...) und der Begruessung lagen:
  wenige Sekunden  -> der Reset selbst hat funktioniert
  ca. 16-20 s      -> erst der Watchdog (sunxi-wdt, max. 16 s) hat zurueckgesetzt
  keine Begruessung -> haengt, Power-Taste noetig

Aufruf: neustart-messen.py logdatei [max_sekunden]   (Standard 360 s)
Exit 0 bei Begruessung, 1 ohne.
"""
import os
import re
import sys
import termios
import time

log = open(sys.argv[1], "ab")
grenze = float(sys.argv[2]) if len(sys.argv) > 2 else 360.0
MARKEN = re.compile(rb"sysrq|Resetting|Restarting|Rebooting|reboot:|watchdog|Reached target .*Reboot|"
                    rb"U-Boot-Konsole|NOTICE|BL3|panic")

fd = os.open("/dev/ttyUSB0", os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
print(time.strftime("%H:%M:%S"), "warte auf den Neustart ...", flush=True)

start = time.time()
puffer = b""
letzter_reset = None
begruessung = None
while time.time() - start < grenze:
	try:
		daten = os.read(fd, 4096)
	except BlockingIOError:
		daten = b""
	jetzt = time.time()
	if not daten:
		if begruessung and jetzt - begruessung > 7:
			break
		time.sleep(0.02)
		continue
	log.write(daten)
	log.flush()
	puffer += daten
	while b"\n" in puffer:
		zeile, puffer = puffer.split(b"\n", 1)
		zeile = zeile.replace(b"\r", b"")
		if MARKEN.search(zeile):
			print(time.strftime("%H:%M:%S", time.localtime(jetzt)), zeile[-150:].decode("ascii", "replace"), flush=True)
			if re.search(rb"Restarting|Resetting|Rebooting\.", zeile):
				letzter_reset = jetzt
			if b"U-Boot-Konsole" in zeile and begruessung is None:
				begruessung = jetzt
	if begruessung is None and b"U-Boot-Konsole" in puffer:
		begruessung = jetzt
os.close(fd)
if begruessung:
	if letzter_reset:
		print("ERGEBNIS: Begruessung %.1f s nach der letzten Reset-Meldung" % (begruessung - letzter_reset), flush=True)
	else:
		print("ERGEBNIS: Begruessung gesehen (keine Reset-Meldung mitgelesen)", flush=True)
	sys.exit(0)
print("ERGEBNIS: keine Begruessung in %.0f s" % grenze, flush=True)
sys.exit(1)
