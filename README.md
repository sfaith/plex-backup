# PlexBackup

![Version](https://img.shields.io/badge/version-0.1.0-blue) ![Platform](https://img.shields.io/badge/platform-Linux-lightgrey) ![Shell](https://img.shields.io/badge/shell-bash-blue) ![License](https://img.shields.io/badge/license-GPL--3.0-green)

A minimal bash script to back up Plex Media Server configuration and databases to a NAS. No media files — just the data that's hard to replace.

---

## Contents

- [What Gets Backed Up](#what-gets-backed-up)
- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Scheduling](#scheduling)
- [Logs](#logs)
- [Planned Scripts](#planned-scripts)

---

## What Gets Backed Up

| Item | Notes |
|---|---|
| Plug-in Support/Databases/ | SQLite databases — watch history, library index, metadata |
| Metadata/ | Downloaded artwork and agent cache |
| Plug-in Support/Preferences/ | Per-plugin settings |
| Preferences.xml | Main Plex configuration file |
| Codecs/, Scanners/, Plug-ins/ | Regeneratable but included for completeness |

**Not backed up:** Cache, Caches, Crash Reports, Logs, Plug-in Support/Caches, and media files.

---

## How It Works

1. Checks that the backup destination is mounted and reachable
2. Stops Plex Media Server
3. Runs rsync to the backup destination (single rolling copy — previous backup is overwritten)
4. Restarts Plex Media Server regardless of rsync result
5. Logs the run and prunes old logs

Plex is restarted even if rsync fails, so a bad backup run never leaves Plex offline.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Linux (Debian/Ubuntu recommended) | Tested on Debian 12 |
| Plex Media Server | Managed via systemd |
| rsync | `apt install rsync` |
| A backup destination | NFS mount, SMB mount, or local path |

---

## Installation

```bash
cp plex-backup.sh.example plex-backup.sh
chmod 700 plex-backup.sh
```

Edit the CONFIG section at the top of `plex-backup.sh` for your environment, then run a syntax check:

```bash
bash -n plex-backup.sh && echo "Syntax OK"
```

Run a dry-run rsync to verify paths before your first live run:

```bash
rsync -aHv --dry-run --no-owner --no-group --no-perms \
    --exclude="Cache/" \
    --exclude="Caches/" \
    --exclude="Crash Reports/" \
    --exclude="Logs/" \
    --exclude="Plug-in Support/Caches/" \
    "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/" \
    "/your/backup/destination/" | head -50
```

---

## Configuration

All configuration lives in the `CONFIG` block at the top of `plex-backup.sh`:

| Variable | Description | Default |
|---|---|---|
| `PLEX_DATA` | Path to Plex Media Server data directory | `/var/lib/plexmediaserver/Library/Application Support/Plex Media Server` |
| `BACKUP_DEST` | Destination path for backup | `/mnt/nfs/your-nas/backups/Plex` |
| `LOG_DIR` | Directory for log files | `/var/log/plex-backup` |
| `PLEX_SERVICE` | systemd service name for Plex | `plexmediaserver` |
| `LOG_RETAIN_DAYS` | Days to keep log files | `7` |

---

## Scheduling

Add to root's crontab (`crontab -e`) to run nightly at 3:00 AM local time (adjust UTC offset for your timezone):

```
0 10 * * * /bin/bash /root/scripts/plex-backup.sh
```

---

## Logs

Logs are written to `LOG_DIR` and named `plex-backup-YYYY-MM-DD.log`. To monitor a run in progress:

```bash
tail -f /var/log/plex-backup/plex-backup-$(date +%Y-%m-%d).log
```

To check the result of the last run:

```bash
tail -20 /var/log/plex-backup/plex-backup-$(date +%Y-%m-%d).log
```

---

## Planned Scripts

| Script | Purpose |
|---|---|
| `plex-restore.sh` | Restore from NAS backup, fix ownership, restart Plex |
| `plex-backup-validate.sh` | SQLite integrity check, backup age validation, required file check |
