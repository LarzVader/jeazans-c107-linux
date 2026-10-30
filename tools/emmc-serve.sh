#!/bin/bash
# Stellt pmos/emmc/ (pmOS-Abbild, Boot-Abbild, schreibe-emmc.sh) per HTTP fuer das Tablet bereit,
# nur auf der USB-Verbindung (172.16.42.2:8000), nicht im LAN. Ende mit Strg+C.
HIER="$(cd "$(dirname "$0")" && pwd)"
exec python3 -m http.server 8000 --bind 172.16.42.2 --directory "$HIER/emmc"
