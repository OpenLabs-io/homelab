# Storage — the ZFS `vault` pool

Every deliberate choice made when building the pool, why it was made, and
what is monitored. The design goal is **drive longevity and data
integrity first**, power draw second.

---

## Topology

```
vault                    ONLINE   2-way mirror, 14.5 TiB usable
  mirror-0               ONLINE
    ata-ST16000NM001G-2KK103_<SERIAL_A>   ONLINE
    wwn-0x<WWN_B>-part1                   ONLINE
```

Single top-level vdev, two-way mirror. No SLOG, no L2ARC, no hot spare,
no special vdev — see [deliberate omissions](#deliberately-not-enabled).

| | |
|---|---|
| Allocated | 6.70 TiB (46%) |
| Fragmentation | 0% |
| Mountpoint | `/vault` (single root dataset, no children) |

Mirror rather than RAIDZ was chosen for resilver behavior: rebuilding a
mirror is a sequential copy of one disk, while RAIDZ resilver is a
random-read workload across every remaining member. On 16 TB drives that
difference decides how long the pool spends degraded and how hard the
surviving disks get worked during the riskiest window in their life.

### A note on the two vdev paths

One member is referenced by its `ata-*` by-id path and the other by
`wwn-*`. That asymmetry is cosmetic — it reflects the order the disks
were added, not a configuration problem. Both are stable `/dev/disk/by-id`
links, which is the part that matters: **never build a pool against
`/dev/sdX`**, because those names are assigned in probe order and can
move between boots.

---

## The drives

| | |
|---|---|
| Model | Seagate Exos X16 `ST16000NM001G-2KK103` |
| Firmware | `SN03` (both) |
| Capacity | 16.0 TB (16,000,900,661,248 bytes) |
| Sector size | 512 B logical / **4096 B physical** (512e) |
| Spindle | 7200 rpm |
| Duty rating | 24×7 enterprise |

Both drives are the same model and firmware revision. Matching members in
a mirror is worth doing — mismatched geometry or cache behavior makes
performance and resilver timing unpredictable.

---

## Pool-level settings

### `ashift=12` — the one you cannot change later

```
vault  ashift  12  local
```

`ashift` is the base-2 log of the smallest block ZFS will write: `12` =
4096 bytes, matching the drives' **physical** sector size.

These are 512e drives — they *report* 512-byte logical sectors while the
platters are 4K. Left to autodetect, ZFS can believe the 512 and pick
`ashift=9`, after which every write becomes a read-modify-write cycle on
the drive: measurable write amplification, worse throughput, and more
mechanical work for the same stored data.

It is set explicitly and it is **immutable**. Changing `ashift` means
destroying and rebuilding the pool. This is the single most important
decision made at creation time.

### Feature flags

Left at the defaults for the installed OpenZFS version. `lz4_compress`,
`large_blocks`, `embedded_data`, `spacemap_histogram`, `extensible_dataset`
and `project_quota` are active; `encryption` is enabled but unused. No
flags were manually enabled, which keeps the pool importable by any
reasonably current OpenZFS.

---

## Dataset properties

Only three properties are set locally. Everything else is inherited
default, deliberately.

```
vault  recordsize  1M    local
vault  atime       off   local
vault  readonly    off   local
```

### `recordsize=1M`

The pool stores large sequential media files. The 128 K default would
split a 4 GB file into ~32,000 records, each with its own checksum and
metadata. At 1 M that drops to ~4,000 — fewer metadata operations, fewer
IOPS, less head movement per gigabyte read.

`recordsize` is a **maximum**, not a fixed size, so small files still
occupy only what they need. It applies to newly written data only;
changing it does not rewrite existing blocks.

### `atime=off`

With `atime` on, every *read* triggers a metadata *write* to record the
access time. On a media library being scanned by Jellyfin, Navidrome,
Lidarr and the \*arr stack, that converts read-only workloads into
constant low-level write traffic, keeps the disks from settling, and
inflates head-park/unpark churn.

Nothing on this pool consumes access times. Turning it off removes an
entire class of pointless writes.

(`relatime=on` is also set but is inert while `atime=off`.)

### Inherited defaults, and why they were left alone

| Property | Value | Reasoning |
|---|---|---|
| `compression` | `on` (lz4) | Nearly free on CPU; already-compressed media simply stores incompressible, so it costs nothing and helps on metadata and text |
| `checksum` | `on` (fletcher4) | Every block verified on read — this is what makes a scrub able to *repair* rather than just detect |
| `copies` | `1` | Redundancy comes from the mirror; `copies=2` would duplicate within each disk and halve usable space for no benefit against whole-disk failure |
| `redundant_metadata` | `all` | Extra metadata copies. Cheap insurance and directly aligned with the longevity goal |
| `sync` | `standard` | Honors application fsync. `disabled` is faster and risks recent writes on power loss |
| `dedup` | `off` | See below |
| `logbias` | `latency` | Correct for this workload |
| `primarycache` | `all` | ARC caches data + metadata. Metadata caching is what lets repeated library scans complete without touching the platters |

### Module parameters

```
zfs_arc_max      = 0   (auto: ARC sizes itself, typically ~50% of RAM)
zfs_arc_min      = 0   (auto)
zfs_txg_timeout  = 5   (default: dirty data flushed at least every 5s)
```

---

## Deliberately not enabled

| | Why not |
|---|---|
| **Dedup** | Needs roughly 1–5 GB RAM per TB of pool and is effectively permanent once data is written. A media library has almost no duplicate blocks. The RAM is far better spent on ARC |
| **SLOG** | Only accelerates *synchronous* writes. This workload is asynchronous bulk media; a SLOG would idle |
| **L2ARC** | Consumes ARC space to index itself. With no RAM pressure, plain ARC is strictly better |
| **Hot spare** | A two-disk mirror in a home server with hands-on access; a spare on the shelf costs nothing to keep and nothing to spin |
| **Native encryption** | Feature flag is enabled but unused. The pool holds no sensitive data and encryption complicates recovery |
| **Drive spindown** | See [longevity policy](#longevity-policy) — rejected on purpose |

---

## Snapshots — sanoid

Config at `/etc/sanoid/sanoid.conf`:

```ini
[vault]
        use_template = production
        recursive = yes

[template_production]
        frequently = 0
        hourly = 24
        daily = 7
        weekly = 4
        monthly = 3
        yearly = 0
        autosnap = yes
        autoprune = yes
```

Snapshots are near-free on a copy-on-write filesystem — they consume space
only as the blocks they pin diverge from the live filesystem. They protect
against accidental deletion and ransomware, **not** against disk failure.
They are not a backup: a snapshot lives on the same pool as its data.

### Timer stretched to 4 hours (2026-09-11)

`sanoid.timer` ships firing every 15 minutes. Overridden at
`/etc/systemd/system/sanoid.timer.d/override.conf`:

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-* 00/4:00:00
```

**Why:** creating a snapshot forces a transaction-group commit — a real
write to the platters. When the pool is otherwise idle the drives park
their heads, and that write reloads them. Every snapshot therefore costs
one head load/unload cycle per drive. Four per hour measured close to
`sdb`'s observed long-run rate of 3.91 cycles/hour, making the snapshot
timer a prime suspect for the bulk of accumulated load-cycle wear.

Trade accepted: worst-case data loss window on `/vault` goes from 1 hour
to 4. Irrelevant for a media library.

> **Gotcha:** `OnCalendar` is *additive* in systemd. The empty
> `OnCalendar=` line is required to clear the vendor value first —
> without it the unit fires on **both** schedules. Verify with:
> ```bash
> systemctl show sanoid.timer -p TimersCalendar   # must list exactly ONE entry
> ```

---

## Scrub and TRIM

From the distribution's `/etc/cron.d/zfsutils-linux`, left at defaults:

```cron
# TRIM  the first  Sunday of every month
# Scrub the second Sunday of every month
```

A scrub reads every allocated block and verifies it against its checksum,
repairing from the mirror on mismatch. This is what turns silent bit rot
into a corrected error and an alert.

Monthly is the right cadence for always-on enterprise drives. The
scheduled TRIM is a no-op on spinning disks and is harmless.

**Last scrub:** 2026-08-09 — `repaired 0B in 08:29:26 with 0 errors`.

> **Scrub only reads *allocated* blocks.** At 46% capacity, more than half
> of each platter is never touched by a scrub. Full-surface verification
> is a SMART long self-test's job, not a scrub's — see
> [known gaps](#known-gaps).

---

## Monitoring and alerting

Three independent layers, all reporting to ntfy rather than to a local
mailbox no one reads:

**1. ZED (ZFS Event Daemon)** — event-driven, reacts in seconds.

```
/etc/zfs/zed.d/statechange-ntfy.sh    vdev state transitions (ONLINE/DEGRADED/FAULTED)
/etc/zfs/zed.d/data-ntfy.sh           checksum / IO error events
```

`zed.rc` keeps `ZED_EMAIL_ADDR="root"` and
`ZED_NOTIFY_INTERVAL_SECS=3600`. The stock email path goes nowhere on a
headless box with no MTA — the custom ntfy hooks above are what actually
deliver.

**2. Cron health checks** (`~/scripts/`, mirrored in `local/host-scripts/`):

| Script | Cadence | Catches |
|---|---|---|
| `check_zfs_health.sh` | every 15 min | pool not ONLINE, read/write/cksum counters |
| `check_snapshots.sh` | twice hourly | sanoid silently stopped taking snapshots |
| `check_scrub_events.sh` | every 10 min | scrub start / finish / repair counts |
| `check_scrub_age.sh` | weekly (Mon) | scrub silently stopped running at all |
| `check_diskspace.sh` | every 6 h | capacity |

The staleness checks matter as much as the error checks. A monitor that
stops running looks identical to a monitor reporting "all clear."

**3. Scrutiny** — SMART attribute dashboard and history.
Collects once daily at 00:00 UTC.

---

## Health baseline — 2026-09-11

| | `sdb` | `sdc` |
|---|---|---|
| Power_On_Hours | 18,555 | 4,615 |
| Temperature | 28 °C | 27 °C |
| Reallocated_Sector_Ct (5) | 0 | 0 |
| Current_Pending_Sector (197) | 0 | 0 |
| Offline_Uncorrectable (198) | 0 | 0 |
| **UDMA_CRC_Error_Count (199)** | **20** (flat) | 0 |
| Start_Stop_Count (4) | 8,088 | 59 |
| **Load_Cycle_Count (193)** | **72,573** (norm 064) | **25,607** (norm 088) |

Media-health attributes are clean on both drives. The `sdb` CRC count of
20 is historical — a bad SATA cable, replaced 2026-06-27. Attribute 199
never resets, so **20 is the floor**; the success signal is that it stays
flat. See [the runbook](runbooks/hdd-smart-crc-errors-cable.md).

### Load cycles are the limiting wear factor

Both drives independently imply a ~200,000-cycle budget from their
normalized values, and both are consuming it fast:

```
sdb  3.91 cycles/hr  →  129,018 remaining  →  ~3.8 years
sdc  5.55 cycles/hr  →  187,784 remaining  →  ~3.9 years
```

Seagate's published Exos X16 figure is 600,000 load/unload cycles, so the
normalized attribute is the pessimistic reading — but it is the number
that will eventually trip a SMART warning, and it is the most-consumed
attribute on the pool. It is therefore the wear metric being managed.

---

## Longevity policy

The explicit priority is **drive life over electricity**. Drives cost
more than power. Consequences:

**Drive spindown is rejected.** Parking the motor would save an estimated
~14 W across the pair — the largest single power saving available on this
machine — but stopping and restarting the spindle is harsher wear than
head parking, and it spends the exact budget being protected. Not
implemented, deliberately.

**Reducing avoidable wake-ups is preferred over saving watts.** The
sanoid change above was made for this reason. The drives stay spinning
24×7, which is what enterprise drives are designed for.

**Wear is measured, not assumed.** Power draw cannot be verified without
a wall meter, which is not available. Load cycles, temperature and
reallocation counts are all readable from SMART, so the longevity goal is
managed against numbers that can actually be checked.

---

## Known gaps

### 1. Docker has no shutdown ordering against the pool

```
docker.service  DropInPaths     = (none)
                After           = (no ZFS unit, no vault.mount)
                TimeoutStopUSec = 1min   (stock default)
```

Nothing orders Docker's shutdown ahead of `vault.mount`, and 41
containers share a 60-second stop budget. On shutdown, containers holding
files open on `/vault` can be killed mid-write, or the unmount can race
them.

ZFS itself is transactional and survives this — the risk is to
*application* state (SQLite databases in the \*arr stack, Postgres for
Immich), and to shutdowns that hang waiting on a timeout.

Intended fix — a drop-in at `/etc/systemd/system/docker.service.d/zfs-ordering.conf`:

```ini
[Unit]
After=vault.mount zfs.target

[Service]
TimeoutStopSec=300
```

`After=` gives ordering in both directions: systemd stops units in
reverse start order, so Docker stops before the pool unmounts.
`Requires=vault.mount` would additionally prevent Docker starting without
the pool, but it is **not** used here — a pool import failure would then
also take down Pi-hole and DNS for the whole network.

### 2. No scheduled SMART self-tests

`smartd` runs, but with the stock `DEVICESCAN` line and no `-s` schedule,
so no periodic short or long tests are configured. Neither pool drive has
a completed self-test in its log.

This matters more than usual here: a scrub verifies only *allocated*
blocks, and the pool is 46% full. Over half of each platter is currently
never read. A long self-test walks the whole surface and surfaces weak
sectors while the mirror is still healthy enough to repair them — rather
than discovering them during a resilver, when redundancy is already gone.

---

## Rebuilding from scratch

The settings that must be re-specified at creation, because they cannot
be changed afterward or do not default correctly:

```bash
zpool create -o ashift=12 \
  -O recordsize=1M \
  -O atime=off \
  -O compression=on \
  vault mirror \
  /dev/disk/by-id/ata-<DISK_A> \
  /dev/disk/by-id/ata-<DISK_B>
```

`ashift` is the only genuinely irreversible one. `recordsize` and `atime`
can be changed later but apply to newly written data only, so setting
them at creation avoids a mixed-layout pool.
