#!/bin/sh
# Laeuft auf dem Tablet als root: sudo sh /home/user/werkzeuge/passwort-und-ssh.sh
# 1. SSH nur noch mit Schluessel. Das Drop-in liegt vor 50-postmarketos-*, weil sshd je
#    Schluesselwort den ersten Wert nimmt; erst nach sshd -t (hier sshd.pam) wird neu geladen.
# 2. Neues Passwort fuer user, der Nutzer tippt es selbst (z. B. eine Zahlen-PIN fuer den
#    Sperrbildschirm). Bis zu 3 Versuche, falls sich die beiden Eingaben unterscheiden.
# 3. Den alten Schluesselbund (gnome-keyring "login", vom 29.10., leer) beiseitelegen: passwd
#    aendert sein Passwort nicht mit, gkr-pam legt beim naechsten Entsperren einen neuen an.
set -eu
zeit() { echo "$(date +%H:%M:%S) $*"; }

conf=/etc/ssh/sshd_config.d/10-jeazans-c107-nur-schluessel.conf
cat > "$conf" <<'EOF'
# Jeazans C107: SSH nur mit Schluessel. Das Passwort von user ist eine kurze PIN fuer
# Sperrbildschirm und sudo und soll uebers Netz nicht zu erraten sein. sshd nimmt je
# Schluesselwort den ersten Wert, darum liegt diese Datei vor 50-postmarketos-*.
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
chmod 644 "$conf"
if ! /usr/sbin/sshd.pam -t; then
	rm -f "$conf"
	zeit "FEHLER: sshd-Konfiguration ungueltig, Datei wieder entfernt, nichts geaendert"
	exit 1
fi
systemctl reload sshd.service
zeit "SSH: $(/usr/sbin/sshd.pam -T | grep -iE '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication) ' | tr '\n' ' ')"

zeit "Neues Passwort fuer user, zweimal eingeben:"
i=1
until passwd user; do
	[ "$i" -ge 3 ] && { zeit "FEHLER: Passwort nicht geaendert, das alte gilt weiter"; exit 1; }
	i=$((i + 1))
	zeit "Nochmal (Versuch $i von 3):"
done

k=/home/user/.local/share/keyrings
stempel=$(date +%Y%m%d-%H%M%S)
for f in login.keyring user.keystore; do
	if [ -f "$k/$f" ]; then mv "$k/$f" "$k/$f.alt-$stempel"; fi
done
zeit "Fertig. Alter Schluesselbund liegt als *.alt-$stempel in $k"
