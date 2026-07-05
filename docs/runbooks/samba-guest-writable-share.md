# Samba share was anonymously writable by the whole LAN

**Date solved:** 2026-07-04 (found during a self-audit)

## Symptom

None — that's the point. The `[vault]` Samba share (the entire 14 TB
media library) had:

```ini
guest ok = yes
writable = yes
```

Any device on the LAN — a guest's phone, a compromised IoT gadget —
could modify or delete everything without a password.

## Root cause

Convenience settings from initial setup, never revisited. "It works"
hid "it works for anyone."

## Fix

Guest *read* is an accepted trade-off on my LAN (media playback from
TVs without credential juggling); guest *write* is not.

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak-$(date +%Y%m%d)
# in /etc/samba/smb.conf, [vault] section:
#   writable = no
```

Validate and reload without dropping active sessions:

```bash
testparm -s                       # parse check BEFORE reloading
sudo smbcontrol all reload-config
```

## Verify

From another machine, mount as guest and attempt a write — it must
fail:

```bash
smbclient //<LAN_IP>/vault -N -c 'put /etc/hostname test.txt'
# expect: NT_STATUS_ACCESS_DENIED
```

## Lesson

Audit shares/permissions as a periodic habit, not once at setup. The
question isn't "does it work for me" but "who *else* does it work
for." ZFS snapshots (Sanoid, every 15 min) are the backstop if a
writable share is ever abused — but a backstop, not a substitute.
