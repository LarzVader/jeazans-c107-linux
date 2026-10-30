#!/usr/bin/env python3
"""Liest die serielle Konsole mit Zeitstempeln mit, als Ergaenzung zu picocom.

Jeder Schub empfangener Bytes bekommt die Uhrzeit, damit sich zuordnen laesst,
welcher Schritt (Neustart, FEL, SPL) welche Ausgabe erzeugt hat. Unlesbare
Bytes erscheinen als \\xNN, zusaetzlich steht der Schub als Hex dahinter.

Aufruf: konsole-zeit.py [Port] [Baud]   (Standard /dev/ttyUSB0, 115200)
Beenden mit Strg+C. picocom darf dabei nicht auf dem Port laufen.
"""
import os
import sys
import termios
import time

port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"
baud = int(sys.argv[2]) if len(sys.argv) > 2 else 115200
baud_const = getattr(termios, f"B{baud}")

fd = os.open(port, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[4] = attrs[5] = baud_const
termios.tcsetattr(fd, termios.TCSANOW, attrs)
termios.tcflush(fd, termios.TCIFLUSH)
print(f"{time.strftime('%H:%M:%S')} hoere auf {port} mit {baud} Baud", flush=True)

schub = b""
letzter = None
try:
	while True:
		try:
			daten = os.read(fd, 4096)
		except BlockingIOError:
			daten = b""
		jetzt = time.time()
		if daten:
			if not schub:
				anfang = jetzt
			schub += daten
			letzter = jetzt
		# Schub ausgeben nach einer Pause oder spaetestens nach 2 s (der SD-Takt auf RXD macht sonst nie Pause)
		if schub and letzter is not None and (jetzt - letzter > 0.25 or jetzt - anfang > 2.0):
			# Schub ist zu Ende: ausgeben
			stempel = time.strftime("%H:%M:%S", time.localtime(anfang)) + f".{int((anfang % 1) * 1000):03d}"
			text = schub.decode("ascii", errors="backslashreplace").replace("\r", "")
			print(f"--- {stempel} {len(schub)} Bytes:", flush=True)
			print(text if text.endswith("\n") else text + "\n", end="", flush=True)
			print("    hex: " + schub.hex(" ")[:600], flush=True)
			schub = b""
		if not daten:
			time.sleep(0.02)
except KeyboardInterrupt:
	pass
finally:
	os.close(fd)
