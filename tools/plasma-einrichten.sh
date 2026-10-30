#!/bin/sh
# Laeuft auf dem Tablet als root: installiert Plasma Mobile (UI-Paket von pmOS) mit Mesa, sperrt
# etnaviv (NPU, damit Mesas kmsro nicht zum falschen Render-Knoten greift), prueft per eglinfo,
# womit EGL ueber simpledrm (card0) rendert, und startet Plasma Mobile.
# Protokoll: /tmp/plasma-einrichtung.log. Aufruf: sudo sh /home/user/werkzeuge/plasma-einrichten.sh
set -eu

haupt() {
	echo "== $(date +%H:%M:%S) etnaviv (NPU) sperren"
	echo "blacklist etnaviv" > /etc/modprobe.d/jeazans-c107-npu.conf
	rmmod etnaviv 2>/dev/null || echo "etnaviv nicht entladen (in Benutzung?)"

	echo "== $(date +%H:%M:%S) Pakete installieren"
	apk add --no-interactive postmarketos-ui-plasma-mobile postmarketos-ui-plasma-mobile-systemd \
		qmlkonsole mesa-dri-gallium mesa-utils

	echo "== DRM-Geraete"
	for c in /sys/class/drm/card[0-9] /sys/class/drm/renderD*; do
		echo "$(basename "$c") -> $(basename "$(readlink -f "$c/device/driver")")"
	done
	echo "== DRI-Treiber: $(ls /usr/lib/xorg/modules/dri/ 2>/dev/null | tr '\n' ' ')"

	echo "== eglinfo als user"
	su -s /bin/sh user -c 'eglinfo -B 2>&1' | grep -i -E "platform|renderer|version string|error|fail" || true

	echo "== $(date +%H:%M:%S) Plasma Mobile einschalten und starten"
	systemctl enable plasma-mobile.service
	systemctl start plasma-mobile.service
	sleep 15
	systemctl --no-pager --lines=0 status plasma-mobile.service | head -5
	echo "== Renderer laut Journal"
	journalctl -b --no-pager | grep -i -E "OpenGL (vendor|renderer|version) string|kms_swrast|llvmpipe|panfrost|kmsro" | tail -8
	echo "== $(date +%H:%M:%S) fertig"
}

haupt 2>&1 | tee /tmp/plasma-einrichtung.log
chmod 644 /tmp/plasma-einrichtung.log
