# NotifIP

LuCI plugin for OpenWrt that sends an email (SMTP) when the WAN IP changes.

- Choice between **public IP** (external HTTP services with fallback + double-check) or **local interface IP(s)**.
- Triggered by cron (configurable interval, default 5 min) **and** by hotplug `ifup` on WAN.
- Liveness mail on the first check after each reboot.
- No anti-flap: one real change = one mail.
- History viewable from LuCI.
- SMTP password stored in `/etc/config/notifip` (root-readable only).

## Requirements

- **OpenWrt 22.03 or newer** (uses client-side JS LuCI views and `network.getNetworks()`).
- `msmtp`, `curl`, `jsonfilter`, `cron` (installed automatically by the installers below).

## Install

### Recommended — `.ipk` from GitHub Releases

CI publishes a noarch `.ipk` on every tag. From the router:

```sh
URL=https://github.com/Kitround/NotifIP/releases/latest/download/luci-app-notifip_all.ipk
# Some firmwares (GL.iNet, custom forks) strip the "arch all" line from /etc/opkg.conf.
# Add it back if missing, then install.
grep -q "^arch all " /etc/opkg.conf || echo "arch all 100" >> /etc/opkg.conf
opkg update
curl -fL -o /tmp/notifip.ipk "$URL"
opkg install /tmp/notifip.ipk
rm /tmp/notifip.ipk
```

Future updates use the exact same command. `/etc/config/notifip` is declared as a conffile, so opkg preserves your SMTP and source settings across upgrades.

### Alternative — `install.sh` script (dev/test, no SDK)

From a clone of this repo on your workstation:

```sh
./install.sh root@192.168.1.1
# or with a custom ssh port:
./install.sh root@192.168.1.1 -p 2222
```

The script copies `files/*` to `/` on the router, installs missing dependencies via `opkg`, and enables the service. Useful when iterating on code, but it **overwrites** `/etc/config/notifip` — back up your SMTP settings first.

### Alternative — Build `.ipk` yourself via the OpenWrt SDK

```sh
cp -r NotifIP <openwrt-sdk>/package/luci-app-notifip
cd <openwrt-sdk>
make package/luci-app-notifip/compile V=s
opkg install bin/packages/*/notifip_feed/luci-app-notifip_*_all.ipk
```

## Configuration

In LuCI: **Services → NotifIP**.

- **Settings tab**: enable, interval, mode (public / interface), full SMTP config, recipient, **Send test mail** button.
- **Sources tab**: ordered list of URLs queried in "public IP" mode (defaults: `ipify`, `ifconfig.me`, `icanhazip`).
- **History tab**: current IP, table of changes, "Clear history" button.

Save & Apply **before** clicking "Send test mail" — the button uses the saved configuration.

## Logs

On the router:

```sh
logread -e notifip               # syslog messages (success/failures)
cat /etc/notifip/changes.log     # TSV history of changes
cat /tmp/msmtp.notifip.log       # last msmtp output (SMTP debug)
```

## Project structure

```
NotifIP/
├── Makefile                                          # OpenWRT package
├── install.sh                                        # scp-based manual installer
├── uninstall.sh                                      # mirror uninstaller
├── LICENSE                                           # MIT
├── files/
│   ├── etc/
│   │   ├── config/notifip                            # UCI defaults
│   │   ├── hotplug.d/iface/30-notifip                # WAN ifup trigger
│   │   └── init.d/notifip                            # cron / service mgmt
│   ├── usr/
│   │   ├── bin/notifip                               # main shell worker
│   │   ├── libexec/rpcd/luci.notifip                 # ubus backend for LuCI
│   │   └── share/
│   │       ├── luci/menu.d/luci-app-notifip.json     # LuCI menu entry
│   │       └── rpcd/acl.d/luci-app-notifip.json      # rpcd ACL
│   └── www/luci-static/resources/view/notifip/
│       ├── settings.js                               # Settings tab
│       ├── sources.js                                # Sources tab
│       └── history.js                                # History tab
└── README.md
```

## Uninstall

Via opkg if installed as `.ipk`:

```sh
opkg remove luci-app-notifip
```

Otherwise (manual install):

```sh
./uninstall.sh root@192.168.1.1
```

## Troubleshooting

- **"msmtp not installed"** in logread → rerun `install.sh` or `opkg install msmtp`.
- **Test mail says Success but no email arrives** → check spam, then `/tmp/msmtp.notifip.log` (often a server rejection after OK auth).
- **`tls_certcheck off`** is used by default to avoid CA store issues on minimal OpenWRT builds. If you install `ca-bundle` and want strict checking, edit `/usr/bin/notifip` (`tls_certcheck on`).
- **Empty tab after install** → `/etc/init.d/rpcd reload` then hard-refresh the browser (Ctrl+F5).
- **535 Authentication failed (OVH, Gmail, etc.)** → wrong password, or 2FA requires an app password, or SMTP auth disabled on the mailbox.
