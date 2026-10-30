#!/usr/bin/env python3
"""Testet den geplanten env_b-Autostart nur im RAM (kein saveenv, nichts wird geflasht).

Ablauf: wartet auf die U-Boot-Begruessung (nach einem Neustart), holt per Strg+C den Prompt,
setzt konsole2/linux/bootcmd2 im RAM und prueft
  A) "run bootcmd2" + Strg+C im 5-s-Fenster -> kein Start, Prompt bleibt
  B) "run bootcmd2" ohne Eingriff -> pmOS startet, Kernel-Zeile mit watchdog.stop_on_reboot=0
Aufruf: autostart-test.py logdatei [--am-prompt]   (--am-prompt: Tablet steht schon am Prompt)
"""
import os
import re
import sys
import termios
import time

# Eingabezeilen am Prompt kurz halten (Hersteller-U-Boot kappt evtl. bei 256 Zeichen)
PINS = ("setexpr.l pf *0x020000f0 & 0xfff0f0ff;setexpr.l pf ${pf} | 0x30300;mw.l 0x020000f0 ${pf};"
        "setexpr.l pb *0x02000034 | 0xff0;mw.l 0x02000034 ${pb}")
KONSOLE = ("run pins2;echo;"
           "echo === Jeazans C107: U-Boot-Konsole am SD-Slot, 5 s Strg+C fuer den Prompt, sonst startet pmOS ===")
LINUX = ("setenv ab_partition_list bootloader,env,boot,vendor_boot,dtbo,vbmeta,vbmeta_system,vbmeta_vendor;"
         "setenv bootargs watchdog.stop_on_reboot=0;sunxi_flash read 0x60000000 boot_b;bootm 0x60000000")
# Kein Hush-Parser im Hersteller-U-Boot (kein if). Der einfache Parser bricht die Befehlskette
# nach einem Befehl ab, waehrend dessen Strg+C kam (had_ctrlc) -> "run linux" entfaellt.
BOOTCMD = "run konsole2;sleep 5;run linux"

log = open(sys.argv[1], "ab")
fd = os.open("/dev/ttyUSB0", os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
termios.tcflush(fd, termios.TCIOFLUSH)


def lies_bis(muster, max_dauer):
	"""Liest, bis eines der Muster (bytes-Regex) auftaucht; gibt (treffer, daten) zurueck."""
	daten = b""
	ende = time.time() + max_dauer
	while time.time() < ende:
		try:
			d = os.read(fd, 4096)
		except BlockingIOError:
			d = b""
		if d:
			log.write(d)
			log.flush()
			daten += d
			m = re.search(muster, daten)
			if m:
				return m.group(0), daten
		else:
			time.sleep(0.02)
	return None, daten


def befehl(text, warte=5.0):
	os.write(fd, text.encode() + b"\r")
	treffer, daten = lies_bis(rb"\n=> $", warte)
	return daten


def melde(text):
	print(time.strftime("%H:%M:%S"), text, flush=True)


if "--am-prompt" not in sys.argv:
	melde("warte auf die U-Boot-Begruessung (bis 10 min) ...")
	treffer, _ = lies_bis(rb"U-Boot-Konsole am SD-Slot", 600)
	if not treffer:
		melde("keine Begruessung")
		sys.exit(1)
	for _ in range(40):
		os.write(fd, b"\x03")
		time.sleep(0.05)
os.write(fd, b"\r")
treffer, _ = lies_bis(rb"=> ", 5)
melde("Prompt da" if treffer else "kein Prompt")

befehl("setenv pins2 '" + PINS + "'")
befehl("setenv konsole2 '" + KONSOLE + "'")
befehl("setenv linux '" + LINUX + "'")
befehl("setenv bootcmd2 '" + BOOTCMD + "'")
daten = befehl("printenv bootcmd2 linux", 5)
melde("im RAM gesetzt: " + " | ".join(z.strip() for z in daten.decode("ascii", "replace").splitlines() if "=" in z))

# Test A: Abbruch im Fenster
os.write(fd, b"run bootcmd2\r")
treffer, _ = lies_bis(rb"sonst startet pmOS", 10)
time.sleep(1.0)
for _ in range(5):
	os.write(fd, b"\x03")
	time.sleep(0.1)
treffer, daten = lies_bis(rb"Starting kernel|sunxi_flash|Android's image", 12)
melde("Test A (Strg+C): " + ("FEHLER, bootet trotzdem: %r" % treffer if treffer else "OK, kein Start, Prompt bleibt"))
lies_bis(rb"=> ", 3)

# Test B: ohne Eingriff
os.write(fd, b"\rrun bootcmd2\r")
treffer, daten = lies_bis(rb"Kernel command line:[^\n]*", 90)
if treffer:
	melde("Test B: Kernel startet, Parameter in der Kernel-Zeile: %s" % (b"watchdog.stop_on_reboot=0" in treffer))
else:
	melde("Test B: FEHLER, kein Kernelstart")
	sys.exit(1)
treffer, _ = lies_bis(rb"Connected to 172\.16\.42\.2|login:", 120)
melde("Test B: " + ("pmOS verbunden/Login" if treffer else "keine NBD-Verbindung in 120 s"))
