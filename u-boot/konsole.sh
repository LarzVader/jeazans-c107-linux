#!/bin/bash
# Serielle Konsole des Tablets (CP2102 an microSD-Sniffer), 115200 Baud (oder BAUD=...).
# Alles Gelesene landet zusaetzlich in konsole-logs/<Datum>.log zum Nachlesen.
# Beenden: Strg+A, dann Strg+X
HIER="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HIER/konsole-logs"
# Andere Geschwindigkeit: BAUD=38400 ./konsole.sh
exec picocom -b "${BAUD:-115200}" --logfile "$HIER/konsole-logs/$(date +%Y-%m-%d_%H-%M-%S).log" "${1:-/dev/ttyUSB0}"
