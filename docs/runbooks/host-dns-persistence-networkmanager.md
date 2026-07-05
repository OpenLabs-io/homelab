# Host DNS kept reverting away from Pi-hole after reboot

**Date solved:** 2026-06-27

## Symptom

The server itself was resolving through 1.1.1.1 / 8.8.8.8 instead of
its own Pi-hole. Editing `/etc/resolv.conf` by hand worked until the
next reboot, when NetworkManager rewrote it from DHCP.

## Root cause

NetworkManager owns `/etc/resolv.conf` and repopulates it from the
DHCP-provided DNS servers on every boot. Hand edits are not persistent
state — the NetworkManager connection profile is.

## Fix

Tell the connection profile to ignore DHCP DNS and pin 127.0.0.1
(Pi-hole listens on :53 on the host):

```bash
# find the active profile name
nmcli connection show --active

nmcli connection modify "<profile>" ipv4.ignore-auto-dns yes
nmcli connection modify "<profile>" ipv4.dns 127.0.0.1
```

Make resolv.conf a symlink to NetworkManager's own copy so nothing
else fights over the file, and force the plain resolver mode:

```bash
sudo ln -sf /run/NetworkManager/resolv.conf /etc/resolv.conf
printf '[main]\ndns=default\n' | sudo tee /etc/NetworkManager/conf.d/dns-mode.conf
sudo systemctl restart NetworkManager
```

## Verify

```bash
cat /etc/resolv.conf          # nameserver 127.0.0.1
resolvectl status 2>/dev/null || nmcli dev show | grep DNS
dig example.com | grep SERVER # ;; SERVER: 127.0.0.1#53
```

Then reboot once and check again — the whole bug was that it *didn't*
survive reboots.

## Resulting DNS chain

```
host/LAN clients → Pi-hole :53 (ad/tracker blocking)
                 → Unbound :5335 (recursive + DNSSEC)
                 → root servers / authoritative NS
```

## Lesson

If a config file keeps reverting, something owns it. Find the owner
(NetworkManager, systemd-resolved, cloud-init, DHCP client) and change
the setting at that layer instead of fighting the file.
