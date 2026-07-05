# SMART CRC errors on a ZFS mirror drive — cable, not drive

**Date solved:** 2026-06-27 (confirmed stable through 2026-07-02)

## Symptom

Scrutiny alerted on `/dev/sdb` (16 TB Seagate, half of the ZFS `vault`
mirror):

- Attribute **199 UDMA_CRC_Error_Count**: 20 and climbing
- Attribute **188 Command_Timeout**: 3 events

## Diagnosis — drive failure or connection?

The deciding evidence: the *media health* attributes were all clean.

```bash
sudo smartctl -A /dev/sdb | grep -E "Reallocated|Pending|Uncorrectable|CRC|Timeout"
```

| Attribute | Value | Meaning |
|-----------|-------|---------|
| 5 Reallocated_Sector_Ct | 0 | platters fine |
| 197 Current_Pending_Sector | 0 | platters fine |
| 198 Offline_Uncorrectable | 0 | platters fine |
| 199 UDMA_CRC_Error_Count | 20 ↑ | **data corrupted in transit** |
| 188 Command_Timeout | 3 | commands lost in transit |

CRC errors happen on the *wire* between drive and controller. CRC
climbing + zero bad sectors = cable/connector problem, not a dying
drive.

## Fix

1. Power down, replace the SATA cable (reseat both ends firmly).
2. Boot, check the pool:

```bash
zpool status vault    # expect: state ONLINE, errors: No known data errors
```

3. **Important:** attribute 199 never resets — 20 is the new floor.
   The success signal is that it *stops climbing*.

## Verify (the follow-up matters)

I left a one-shot cron script running for a few days that re-polled
Scrutiny's API for attr 188/199 and pushed an ntfy notification with
"unchanged / increased" — counts stayed flat, cable swap confirmed.

If CRC resumes climbing after a cable swap: try a different SATA port,
then suspect the backplane/controller before condemning the drive.

## Lesson

Learn which SMART attributes mean "drive dying" (5, 197, 198) vs
"connection bad" (199, 188). They call for opposite responses — one is
an RMA, the other is a $5 cable.
