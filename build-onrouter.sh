#!/usr/bin/env bash
# Generates install-on-router.sh: a single self-extracting script
# to run inside the OpenWRT router shell.
#
# Usage: ./build-onrouter.sh

set -euo pipefail
cd "$(dirname "$0")"

OUT=install-on-router.sh
PAYLOAD=$(cd files && tar -cf - . | gzip -9 | base64)

cat > "$OUT" <<'HEADER'
#!/bin/sh
# NotifIP — self-extracting on-router installer.
# Run it on the OpenWRT router, ideally piped through ssh:
#   ssh root@<router> sh < install-on-router.sh
# (pasting 15 KB in the terminal can drop the ssh connection).

set -e

have() { command -v "$1" >/dev/null 2>&1; }

echo "==> Checking base64 decoder …"
B64=""
if have base64; then
	B64="base64 -d"
elif have openssl; then
	B64="openssl base64 -d"
else
	echo "    base64 missing, installing via opkg …"
	opkg update >/dev/null 2>&1 || true
	opkg install coreutils-base64 2>/dev/null \
		|| opkg install openssl-util 2>/dev/null \
		|| true
	if have base64; then
		B64="base64 -d"
	elif have openssl; then
		B64="openssl base64 -d"
	else
		echo "ERROR: cannot install base64 or openssl." >&2
		echo "Install manually: opkg install coreutils-base64" >&2
		exit 1
	fi
fi

echo "==> Extracting NotifIP files …"
$B64 <<'PAYLOAD' | gzip -d | tar -xf - -C /
HEADER

printf '%s\n' "$PAYLOAD" >> "$OUT"

cat >> "$OUT" <<'FOOTER'
PAYLOAD

echo "==> Setting ownership, executable bits, tightening config …"
chown -R 0:0 /usr/bin/notifip \
             /etc/init.d/notifip \
             /etc/hotplug.d/iface/30-notifip \
             /usr/libexec/rpcd/luci.notifip \
             /usr/share/luci/menu.d/luci-app-notifip.json \
             /usr/share/rpcd/acl.d/luci-app-notifip.json \
             /www/luci-static/resources/view/notifip \
             /etc/config/notifip 2>/dev/null || true
chmod 0755 /usr/bin/notifip \
           /etc/init.d/notifip \
           /etc/hotplug.d/iface/30-notifip \
           /usr/libexec/rpcd/luci.notifip
# Config holds the SMTP password — restrict to root
chmod 0600 /etc/config/notifip 2>/dev/null || true

echo "==> Installing missing dependencies …"
NEED=""
command -v msmtp      >/dev/null 2>&1 || NEED="$NEED msmtp"
command -v curl       >/dev/null 2>&1 || NEED="$NEED curl"
command -v jsonfilter >/dev/null 2>&1 || NEED="$NEED jsonfilter"
command -v crond      >/dev/null 2>&1 || NEED="$NEED cron"
if [ ! -f /etc/ssl/certs/ca-certificates.crt ] \
&& [ ! -f /etc/ssl/cert.pem ] \
&& [ ! -f /etc/ssl/certs/ca-bundle.crt ]; then
	NEED="$NEED ca-bundle"
fi

if [ -n "$NEED" ]; then
	echo "    Packages to install: $NEED"
	opkg update
	# shellcheck disable=SC2086
	opkg install $NEED
else
	echo "    All dependencies already present."
fi

echo "==> Enabling services …"
/etc/init.d/rpcd reload    2>/dev/null || true
/etc/init.d/cron enable    2>/dev/null || true
/etc/init.d/cron start     2>/dev/null || true
/etc/init.d/notifip enable 2>/dev/null || true
/etc/init.d/notifip start  2>/dev/null || true

cat <<DONE

==> Installation done.

Open LuCI in your browser:
    Services → NotifIP

1. Settings tab: tick "Enabled", fill in SMTP and recipient.
2. Save & Apply.
3. Click "Send test mail" → check your mailbox.

Logs on the router:
    logread -e notifip
    cat /etc/notifip/changes.log
    cat /tmp/msmtp.notifip.log
DONE
FOOTER

chmod +x "$OUT"
SIZE=$(wc -c < "$OUT")
echo "Generated: $OUT (${SIZE} bytes)"
