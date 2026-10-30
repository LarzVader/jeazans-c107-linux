#!/usr/bin/env python3
"""Zeichnet aus einem evtest-Mitschnitt des Touch-Treibers eine Karte der erkannten Stellen.
Aufruf: touch-karte.py touch-ev.txt
Treiber-Koordinaten sind die des Panels (hochkant). Die Karte zeigt die normale Querlage:
links im Bild = obere Panelkante, oben im Bild = rechte Panelkante."""
import re
import sys

zeilen = open(sys.argv[1], errors="replace").read().splitlines()
maxx = maxy = None
for z in zeilen:
    m = re.search(r"Event code (\d+) \(ABS_MT_POSITION_([XY])\)", z)
    if m:
        ach = m.group(2)
    m = re.match(r"\s+Max\s+(\d+)", z)
    if m and "ach" in dir():
        if ach == "X" and maxx is None:
            maxx = int(m.group(1))
        elif ach == "Y" and maxy is None:
            maxy = int(m.group(1))
print(f"Treiber-Bereich: X 0..{maxx}, Y 0..{maxy}")

punkte = []
slots = {}
slot = 0
beruehrungen = 0
for z in zeilen:
    m = re.search(r"code \d+ \((ABS_MT_\w+)\), value (-?\d+)", z)
    if not m:
        continue
    name, wert = m.group(1), int(m.group(2))
    if name == "ABS_MT_SLOT":
        slot = wert
    elif name == "ABS_MT_TRACKING_ID":
        if wert >= 0:
            beruehrungen += 1
    elif name == "ABS_MT_POSITION_X":
        slots.setdefault(slot, [0, 0])[0] = wert
        punkte.append(tuple(slots[slot]))
    elif name == "ABS_MT_POSITION_Y":
        slots.setdefault(slot, [0, 0])[1] = wert
        punkte.append(tuple(slots[slot]))

print(f"{len(punkte)} Positionswerte, {beruehrungen} Beruehrungen")
if not punkte:
    sys.exit("keine Positionswerte im Mitschnitt")
xs = [p[0] for p in punkte]
ys = [p[1] for p in punkte]
print(f"erreicht: X {min(xs)}..{max(xs)}, Y {min(ys)}..{max(ys)}")

BREITE, HOEHE = 72, 24
gitter = [[0] * BREITE for _ in range(HOEHE)]
for x, y in punkte:
    # Querlage: links = Panel oben (Y klein), oben = Panel rechts (X gross)
    sp = min(BREITE - 1, y * BREITE // (maxy + 1))
    ze = min(HOEHE - 1, (maxx - x) * HOEHE // (maxx + 1))
    gitter[ze][sp] += 1

print("Karte in normaler Querlage (. = nie erkannt, # = erkannt):")
print("+" + "-" * BREITE + "+")
for reihe in gitter:
    print("|" + "".join("#" if w else "." for w in reihe) + "|")
print("+" + "-" * BREITE + "+")
# Ecken: kleinster Abstand eines Punkts zur jeweiligen Ecke in Treiber-Einheiten
ecken = {
    "oben links": (maxx, 0),
    "oben rechts": (maxx, maxy),
    "unten links": (0, 0),
    "unten rechts": (0, maxy),
}
for name, (ex, ey) in ecken.items():
    d = min(((x - ex) ** 2 + (y - ey) ** 2) ** 0.5 for x, y in punkte)
    print(f"{name:13s}: naechster Punkt {d:5.0f} Einheiten von der Ecke (rund {d * 800 / (maxx + 1) * 0.135:4.1f} mm)")
