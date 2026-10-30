#!/usr/bin/env python3
"""Notaus fuer die Tests mit dem echten Displaytreiber. Laeuft auf dem Tablet als root.

Scharf schalten:  sudo python3 ~/werkzeuge/display-notaus.py [--sekunden N] [--nur-schiene]
Ausloesen:
  - Ein/Aus-Taste kurz oder Leiser: sofort,
  - Ablauf der Zeit (Totmann, Standard 60 s), Lauter verlaengert um die eingestellte Zeit,
  - vom PC ohne sudo: tablet-ssh.sh touch /tmp/notaus
  - Strg+C oder SIGTERM.
Der einzige Ausgang ohne Abschalten ist ausdruecklich: tablet-ssh.sh touch /tmp/notaus-ende

Wirkung: Hintergrundlicht aus und Panel-Schiene CLDO4 der AXP717 aus (Register 0x91, Bit 3). Die
Schiene versorgt laut Hersteller-DT nur das Panel. Sie wird direkt per I2C geschaltet, am Treiber
vorbei, damit das auch dann geht, wenn der Displaytreiber haengt. Haengt der ganze Kernel, greifen
der Watchdog (Neustart nach 15 s) und langes Halten der Ein/Aus-Taste (schaltet die PMIC selbst ab).

Zurueck:  --schiene-an, dann Neustart (das Panel initialisiert bisher nur der Hersteller-U-Boot).
"""
import argparse
import ctypes
import fcntl
import glob
import os
import select
import signal
import struct
import subprocess
import time

PMIC_ADRESSE = 0x34
REG_LDO1 = 0x91
BIT_CLDO4 = 1 << 3
I2C_RDWR = 0x0707
I2C_M_RD = 0x0001
TRIGGER = "/tmp/notaus"
ENDE = "/tmp/notaus-ende"
EV_KEY = 1
KEY_VOLUMEDOWN, KEY_VOLUMEUP, KEY_POWER = 114, 115, 116
TASTEN = ("axp20x-pek", "2009800.lradc")
EREIGNIS = struct.Struct("qqHHi")  # struct input_event auf 64 Bit


class I2cMsg(ctypes.Structure):
    _fields_ = [("addr", ctypes.c_uint16), ("flags", ctypes.c_uint16),
                ("len", ctypes.c_uint16), ("buf", ctypes.POINTER(ctypes.c_uint8))]


class I2cRdwr(ctypes.Structure):
    _fields_ = [("msgs", ctypes.POINTER(I2cMsg)), ("nmsgs", ctypes.c_uint32)]


class Pmic:
    """Register der AXP717. I2C_RDWR ist atomar und nimmt auch Adressen, die ein Treiber belegt."""

    def __init__(self):
        subprocess.run(["modprobe", "i2c-dev"], check=False)
        pfad = glob.glob(f"/sys/bus/i2c/devices/*-{PMIC_ADRESSE:04x}")[0]
        self.fd = os.open("/dev/i2c-" + os.path.basename(pfad).split("-")[0], os.O_RDWR)

    def _transfer(self, *teile):
        msgs = (I2cMsg * len(teile))()
        puffer = []
        for i, (flags, daten) in enumerate(teile):
            p = (ctypes.c_uint8 * len(daten))(*daten)
            puffer.append(p)
            msgs[i] = I2cMsg(PMIC_ADRESSE, flags, len(daten), p)
        fcntl.ioctl(self.fd, I2C_RDWR, I2cRdwr(msgs, len(teile)))
        return puffer

    def lesen(self, reg):
        return self._transfer((0, [reg]), (I2C_M_RD, [0]))[1][0]

    def schreiben(self, reg, wert):
        self._transfer((0, [reg, wert]))

    def cldo4(self, an):
        wert = self.lesen(REG_LDO1)
        neu = wert | BIT_CLDO4 if an else wert & ~BIT_CLDO4
        self.schreiben(REG_LDO1, neu)
        return wert, self.lesen(REG_LDO1)


def licht_aus():
    for pfad in glob.glob("/sys/class/backlight/*/brightness"):
        with open(pfad, "w") as f:
            f.write("0")


def tasten_oeffnen():
    fds = {}
    for geraet in glob.glob("/sys/class/input/event*"):
        with open(geraet + "/device/name") as f:
            name = f.read().strip()
        if name in TASTEN:
            fds[os.open("/dev/input/" + os.path.basename(geraet), os.O_RDONLY | os.O_NONBLOCK)] = name
    return fds


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sekunden", type=int, default=60, help="Totmann-Zeit, Lauter verlaengert um sie")
    ap.add_argument("--nur-schiene", action="store_true", help="Probe: Licht bleibt an, nur CLDO4 aus")
    ap.add_argument("--nur-licht", action="store_true", help="Probe: nur das Hintergrundlicht aus")
    ap.add_argument("--schiene-an", action="store_true", help="CLDO4 wieder ein und beenden")
    a = ap.parse_args()

    pmic = Pmic()
    if a.schiene_an:
        alt, neu = pmic.cldo4(True)
        print(f"CLDO4 an: Register 0x91 {alt:#04x} -> {neu:#04x}", flush=True)
        return

    for pfad in (TRIGGER, ENDE):
        if os.path.exists(pfad):
            os.remove(pfad)
    fds = tasten_oeffnen()
    stopp = []
    for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, lambda nr, _: stopp.append(signal.Signals(nr).name))

    ende = time.monotonic() + a.sekunden
    print(f"NOTAUS SCHARF, Tasten: {', '.join(fds.values())}. Aus nach {a.sekunden} s, "
          f"Lauter verlaengert, Ein/Aus oder Leiser sofort.", flush=True)
    grund = None
    druck = None
    letzte_anzeige = None
    while grund is None:
        rest = ende - time.monotonic()
        if rest <= 0:
            grund = "Zeit abgelaufen"
            break
        if stopp:
            grund = stopp[0]
            break
        if os.path.exists(TRIGGER):
            grund = TRIGGER
            break
        if os.path.exists(ENDE):
            print("Notaus beendet, nichts abgeschaltet", flush=True)
            return
        anzeige = int(rest) // 10
        if anzeige != letzte_anzeige:
            print(f"  noch {int(rest)} s", flush=True)
            letzte_anzeige = anzeige
        try:
            bereit, _, _ = select.select(list(fds), [], [], min(rest, 0.05))
        except InterruptedError:
            continue
        for fd in bereit:
            for i in range(0, len(daten := os.read(fd, 240)), EREIGNIS.size):
                sek, usek, typ, code, wert = EREIGNIS.unpack_from(daten, i)
                if typ != EV_KEY or wert != 1:
                    continue
                if code == KEY_VOLUMEUP:
                    ende = time.monotonic() + a.sekunden
                    print(f"  Lauter: wieder {a.sekunden} s", flush=True)
                    letzte_anzeige = None
                elif code in (KEY_POWER, KEY_VOLUMEDOWN):
                    grund = "Ein/Aus" if code == KEY_POWER else "Leiser"
                    druck = sek + usek / 1e6

    if not a.nur_schiene:
        licht_aus()
    if not a.nur_licht:
        alt, neu = pmic.cldo4(False)
    else:
        alt = neu = pmic.lesen(REG_LDO1)
    dauer = f", {(time.time() - druck) * 1000:.0f} ms nach dem Druck" if druck else ""
    print(f"NOTAUS: {grund}{dauer}. Register 0x91 {alt:#04x} -> {neu:#04x}", flush=True)


if __name__ == "__main__":
    main()
