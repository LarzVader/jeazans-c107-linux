#!/usr/bin/env python3
"""Liest die serielle Konsole waehrend eines Rettungslaufs mit und endet bei FERTIG.

Wie konsole-zeit.py (Zeitstempel je Schub), aber beendet sich selbst, sobald eine
Abschlusszeile (FERTIG / FERTIG MIT PROBLEMEN / FERTIG OHNE VOLLE PRUEFUNG) kam oder
die Zeit abgelaufen ist. Dadurch meldet sich der Hintergrundlauf von selbst zurueck.

Aufruf: rettung-lesen.py [Port] [Sekunden]   (Standard /dev/ttyUSB0, 150 s)
Waehrend des Laufs ist am CP2102 nur RXD und GND angeschlossen (TXD ab), also nur Lesen.
"""
import os
import re
import sys
import termios
import time

port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"
grenze = float(sys.argv[2]) if len(sys.argv) > 2 else 150.0

fd = os.open(port, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
termios.tcflush(fd, termios.TCIFLUSH)
print(f"{time.strftime('%H:%M:%S')} hoere auf {port}, warte bis {grenze:.0f} s auf FERTIG", flush=True)

ende = time.time() + grenze
schub = b""
anfang = letzter = None
gesamt = b""
fertig = False
while time.time() < ende and not fertig:
	try:
		daten = os.read(fd, 4096)
	except BlockingIOError:
		daten = b""
	jetzt = time.time()
	if daten:
		if not schub:
			anfang = jetzt
		schub += daten
		gesamt += daten
		letzter = jetzt
	if schub and letzter is not None and (jetzt - letzter > 0.25 or jetzt - anfang > 2.0):
		stempel = time.strftime("%H:%M:%S", time.localtime(anfang))
		# nur Zeilen mit lesbarem Anteil zeigen (SD-Takt-Muell unterdruecken): Anteil und
		# Woerter an den Rohbytes messen, denn "\xff" waere nach backslashreplace lesbar,
		# und der SD-Takt kommt als "UU\xff" an (0x55 = Takt), also mind. drei Buchstaben am Stueck
		for roh in schub.replace(b"\r", b"").split(b"\n"):
			lesbar = sum(32 <= b < 127 for b in roh)
			if (lesbar > 0.8 * len(roh) and re.search(rb"[A-Za-z]{3,}", roh)
					and re.search(rb"[A-TV-Za-z]", roh) and b"xit ok" not in roh):
				zeile = roh[:300].decode("ascii", errors="backslashreplace")
				print(f"{stempel}  {zeile}", flush=True)
		if b"FERTIG" in gesamt:
			fertig = True
		schub = b""
	if not daten:
		time.sleep(0.02)
os.close(fd)
if b"FERTIG OHNE VOLLE PRUEFUNG" in gesamt:
	print("ERGEBNIS: FERTIG OHNE VOLLE PRUEFUNG", flush=True)
elif b"FERTIG MIT PROBLEMEN" in gesamt:
	print("ERGEBNIS: FERTIG MIT PROBLEMEN", flush=True)
elif b"FERTIG" in gesamt:
	print("ERGEBNIS: FERTIG", flush=True)
else:
	print("ERGEBNIS: kein FERTIG gesehen (Zeit abgelaufen)", flush=True)
