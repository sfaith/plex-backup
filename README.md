# plex-backup

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
- [Validation](#validation)
- [Alerting](#alerting)
- [Logs](#logs)
- [Planned](#planned)

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

**plex-backup.sh:**
1. Checks that the backup destination is mounted and reachable
2. Stops Plex Media Server
3. Runs rsync to the backup destination (single rolling copy — previous backup is overwritten)
4. Restarts Plex Media Server regardless of rsync result
5. Sends ntfy alert on failure or success (if configured)
6. Logs the run and prunes old logs

**plex-backup-validate.sh** (run separately, zero Plex downtime):
1. Checks that the backup destination is mounted and reachable
2. Verifies the backup is not older than the configured threshold
3. Confirms all critical files are present and reports their size
4. Reports total backup size
5. Sends ntfy alert on pass or failure (if configured)

Plex is restarted even if rsync fails, so a bad backup run never leaves Plex offline.

> **Note:** The first backup will transfer your entire Plex data directory and may take several hours depending on library size and NAS speed. Subsequent runs are incremental and typically complete in a few minutes.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Linux (Debian/Ubuntu recommended) | Tested on Debian 12 |
| Plex Media Server | Managed via systemd |
| rsync | `apt install rsync` |
| curl | Required for ntfy alerting; `apt install curl` |
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

All configuration lives in the `CONFIG` block at the top of each script:

### plex-backup.sh

| Variable | Description | Default |
|---|---|---|
| `PLEX_DATA` | Path to Plex Media Server data directory | `/var/lib/plexmediaserver/Library/Application Support/Plex Media Server` |
| `BACKUP_DEST` | Destination path for backup | `/mnt/nfs/your-nas/backups/Plex` |
| `LOG_DIR` | Directory for log files | `/var/log/plex-backup` |
| `PLEX_SERVICE` | systemd service name for Plex | `plexmediaserver` |
| `LOG_RETAIN_DAYS` | Days to keep log files | `7` |
| `NTFY_TOPIC` | ntfy topic name — set to `""` to disable | `""` |
| `NTFY_URL` | ntfy server URL | `https://ntfy.sh` |
| `NTFY_ON_FAILURE` | Send alert on backup failure | `true` |
| `NTFY_ON_SUCCESS` | Send alert on backup success | `false` |

### plex-backup-validate.sh

| Variable | Description | Default |
|---|---|---|
| `BACKUP_ROOT` | Root path of the Plex backup on your NAS | `/mnt/nfs/your-nas/backups/Plex` |
| `LOG_DIR` | Directory for log files | `/var/log/plex-backup` |
| `WARN_AGE_HOURS` | Warn if backup is older than this many hours | `25` |
| `LOG_RETAIN_DAYS` | Days to keep log files | `7` |
| `NTFY_TOPIC` | ntfy topic name — set to `""` to disable | `""` |
| `NTFY_URL` | ntfy server URL | `https://ntfy.sh` |
| `NTFY_ON_FAILURE` | Send alert on validation failure | `true` |
| `NTFY_ON_SUCCESS` | Send alert on validation success | `false` |

---

## Scheduling

Add to root's crontab (`crontab -e`). The example below runs the backup at 3:00 AM and validation 30 minutes later (adjust UTC offset for your timezone):

```
0 10 * * * /bin/bash /root/scripts/plex-backup.sh
30 10 * * * /bin/bash /root/scripts/plex-backup-validate.sh
```

---

## Validation

`plex-backup-validate.sh` runs entirely against the NAS copy — Plex is never touched. It checks:

- **NFS mount** — aborts if the backup destination is unreachable
- **Backup age** — warns if the backup is older than `WARN_AGE_HOURS` (catches missed cron runs)
- **Required files** — confirms critical databases and Preferences.xml are present and reports their size
- **Total backup size** — gross sanity check

**Note on SQLite integrity checks:** Plex's main library databases use a proprietary SQLite tokenizer that the system `sqlite3` binary does not support. Integrity checks against these files always fail with `unknown tokenizer: collating` regardless of whether the data is corrupt. This is a Plex limitation, not a script deficiency — the validate script documents this decision in its header comments.

---

## Alerting

Both scripts support [ntfy](https://ntfy.sh) push notifications. Set `NTFY_TOPIC` to your topic name to enable:

```bash
NTFY_TOPIC="your-topic-name"
NTFY_URL="https://ntfy.sh"   # change for self-hosted ntfy
NTFY_ON_FAILURE=true
NTFY_ON_SUCCESS=false
```

Leave `NTFY_TOPIC=""` to disable alerting entirely. `curl` must be installed.

---

## Logs

Logs are written to `LOG_DIR` and named by date. To monitor a run in progress:

```bash
tail -f /var/log/plex-backup/plex-backup-$(date +%Y-%m-%d).log
```

To check the result of the last validation:

```bash
tail -20 /var/log/plex-backup/plex-validate-$(date +%Y-%m-%d).log
```

---

## Planned

- `plex-restore.sh` — restore from NAS backup, fix file ownership, restart Plex
- `plex-backup.conf` — shared config file sourced by all scripts (eliminates duplicate config blocks)
- Tautulli backup support — optional, toggled via `TAUTULLI_ENABLED`
