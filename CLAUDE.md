# NotifIP — Claude context

LuCI plugin for OpenWRT. Sends an email via SMTP when the WAN IP changes.

## Stack
- Worker: `files/usr/bin/notifip` (POSIX sh, busybox-compatible)
- Init: `files/etc/init.d/notifip` (procd, manages cron line in `/etc/crontabs/root`)
- Hotplug: `files/etc/hotplug.d/iface/30-notifip` (fires on `ifup wan*`)
- LuCI views (JS): `files/www/luci-static/resources/view/notifip/{settings,sources,history}.js`
- rpcd backend: `files/usr/libexec/rpcd/luci.notifip` (exposes `status`, `log`, `test_mail`, `clear_log` over ubus)
- UCI: `files/etc/config/notifip` with sections `general`, `smtp`, `sources`

## Design decisions (resolved in earlier grilling)
- Modes: `public` (HTTP services, ordered list + double-check with a 2nd source on change) or `iface` (ubus ifstatus).
- IPv4 only.
- Trigger: cron (default 5 min) + hotplug. Mutex via `flock`.
- State persistent in `/etc/notifip/state`. Boot mail (signal of life) on first run after reboot, tracked via `/tmp/notifip.booted`.
- Failure to reach all sources → log only, no mail, no state change.
- No anti-flap: 1 real change = 1 mail.
- Log TSV in `/etc/notifip/changes.log`, rotation at 500 lines.
- SMTP via `msmtp`, config written to `/etc/msmtprc.notifip` (chmod 600).

## Install
- Primary: `./install.sh root@<router>` (uses `tar | ssh`, sets ownership root:root, chmod 600 on config).
- Secondary: `.ipk` via OpenWRT SDK (`Makefile` provided).
- Self-extracting: `./build-onrouter.sh` generates `install-on-router.sh`. Run with `ssh root@<router> sh < install-on-router.sh` (do NOT paste — terminal buffer drops connection on large pastes).

## Dependencies (installed by install.sh if missing)
`msmtp`, `curl`, `jsonfilter`, `cron`, `ca-bundle` (optional, enables TLS cert verification).

## Security posture
- `/etc/config/notifip` mode 0600 (contains SMTP password in plaintext) — enforced on every init reload and worker run.
- `tls_certcheck` auto-enabled if a CA bundle exists, else `off`. Acceptable for home use (router stays on trusted LAN). Document only.
- Hostname is stripped of CR/LF before mail headers.
- URL loops wrapped in `set -f` to block glob expansion.

## Known quirks
- busybox ash: `local var1=x var2=y var3=""` can misparse the last `=""` — declare locals separately. Already fixed in `write_msmtprc()`.
- macOS `scp` defaults to SFTP protocol; OpenWRT busybox has no sftp-server. Use `scp -O` (legacy) or `install.sh` (uses tar over ssh).
- LuCI auto-translates common strings (`Settings`, `History`, `Sources`) via its locale pack. To force English UI, set LuCI language to English in System → System → Language and Style.
- The `Send test mail` button uses the *saved* UCI config — always Save & Apply first.

## SMTP — common authentication failures
- `535 5.7.1 Authentication failed` → wrong password, 2FA needs an app password, or SMTP-auth disabled on the mailbox (provider config issue, not NotifIP).
- OVH: `ssl0.ovh.net:465` SMTPS or `smtp.mail.ovh.net:587` STARTTLS. Do not mix.

## Useful router-side commands
```sh
logread -e notifip               # syslog messages
cat /etc/notifip/changes.log     # change history
cat /tmp/msmtp.notifip.log       # last msmtp run (TLS / auth errors)
/usr/bin/notifip test-mail       # trigger a test mail manually
/usr/bin/notifip status          # JSON state
/etc/init.d/notifip reload       # reapply cron after manual UCI edit
```

## Do not
- Edit `/etc/msmtprc.notifip` directly — overwritten on every send.
- Touch `/etc/crontabs/root` lines tagged `# notifip` — managed by the init script.
- Add anti-flap, multi-recipient, or per-provider SMTP presets without re-grilling — explicitly rejected in earlier design discussion.
