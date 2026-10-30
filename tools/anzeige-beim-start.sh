#!/bin/sh
# Laeuft auf dem Tablet als root (ein sudo fuer alles): laedt den Uebernahme-Treiber sun55i_takeover
# ab dem naechsten Start von selbst, bevor der Desktop kommt, und startet neu. Das ist der Weg zum
# Desktop-Test: Den laufenden Desktop umzuziehen geht nicht, denn KWin laeuft als Nutzerdienst weiter,
# wenn plasma-mobile.service stoppt, und verliert dabei seine logind-Sitzung (am 30.10. so gesehen).
# Solange der Test laeuft, wird auch der Notaus mitgestartet (15 min Totmann, Lauter verlaengert,
# Ein/Aus oder Leiser sofort). Beenden ohne Abschalten: tablet-ssh.sh touch /tmp/notaus-ende
# Aufruf: sudo sh /home/user/werkzeuge/anzeige-beim-start.sh an|aus|weg
#   aus nimmt das zurueck und startet neu, weg nimmt es zurueck, ohne neu zu starten (wenn das
#   Geraetepaket das Laden uebernimmt). Ein laufender Notaus bleibt dann bis zum Neustart scharf.
set -eu
LADEN=/etc/modules-load.d/sun55i-takeover.conf
DIENST=/etc/systemd/system/anzeige-notaus.service

case "${1:-}" in
an)
	echo sun55i_takeover > "$LADEN"
	cat > "$DIENST" <<-'EOF'
		[Unit]
		Description=Notaus fuer den Test des Anzeige-Treibers
		After=systemd-modules-load.service

		[Service]
		# Die Tasten-Treiber sind Module, sie brauchen nach dem Start einen Moment
		ExecStartPre=sleep 5
		ExecStart=python3 /home/user/werkzeuge/display-notaus.py --sekunden 900

		[Install]
		WantedBy=multi-user.target
	EOF
	systemctl enable anzeige-notaus.service
	;;
aus|weg)
	systemctl disable anzeige-notaus.service || true
	rm -f "$LADEN" "$DIENST"
	;;
*)
	echo "Aufruf: $0 an|aus|weg"
	exit 1
	;;
esac
systemctl daemon-reload
[ "$1" = weg ] && exit 0
echo "Treiber beim Start: $1. Neustart."
sync
reboot
