#!/usr/bin/env python3
"""Beobachtet einen Start mit env_b-Autostart, ohne etwas zu senden (kein Strg+C!).

Zeigt die wichtigen Stationen mit Uhrzeit (Reset-Meldung, U-Boot-Begruessung, bootm, Kernel-Zeile
mit/ohne watchdog.stop_on_reboot=0, NBD-Verbindung, Login) und endet beim Login oder nach der
Wartezeit. Alles Gelesene geht roh in die Logdatei.
Aufruf: autostart-beobachten.py logdatei [max_sekunden] [nach-reset]   (Standard 300 s)
  nach-reset: Login erst nach einer Reset-Meldung oder der U-Boot-Begruessung zaehlen
  (sonst beendet eine neue Login-Zeile vor dem Neustart, z. B. bei apk-Updates, zu frueh).
Exit 0 beim Login, 1 ohne.
"""
import os
import re
import sys
import termios
import time

log = open(sys.argv[1], "ab")
grenze = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
reset_gesehen = "nach-reset" not in sys.argv[3:]
MUSTER = re.compile(rb"Restarting system|sysrq: Resetting|U-Boot-Konsole|Unknown command|Android's image|"
                    rb"Starting kernel|Kernel command line|Connected to|login:|Kernel panic|=> ")

fd = os.open("/dev/ttyUSB0", os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
print(time.strftime("%H:%M:%S"), "beobachte (nur lesen) ...", flush=True)

ende = time.time() + grenze
puffer = b""
gesehen = set()
while time.time() < ende:
	try:
		daten = os.read(fd, 4096)
	except BlockingIOError:
		daten = b""
	if not daten:
		time.sleep(0.02)
		continue
	log.write(daten)
	log.flush()
	puffer += daten
	while b"\n" in puffer:
		zeile, puffer = puffer.split(b"\n", 1)
		zeile = zeile.replace(b"\r", b"")
		m = MUSTER.search(zeile)
		if not m or m.group(0) in gesehen:
			continue
		gesehen.add(m.group(0))
		text = zeile.decode("ascii", "replace")
		if m.group(0) == b"Kernel command line":
			text = "Kernel-Zeile %s watchdog.stop_on_reboot=0" % (
				"MIT" if b"watchdog.stop_on_reboot=0" in zeile else "OHNE")
		print(time.strftime("%H:%M:%S"), text[-140:], flush=True)
		if m.group(0) in (b"Restarting system", b"sysrq: Resetting", b"U-Boot-Konsole"):
			reset_gesehen = True
	if reset_gesehen and (b"login:" in puffer or b"login:" in daten):
		print(time.strftime("%H:%M:%S"), "Login erreicht", flush=True)
		sys.exit(0)
print(time.strftime("%H:%M:%S"), "kein Login in %.0f s" % grenze, flush=True)
sys.exit(1)
