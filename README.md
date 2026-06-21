# plex-backup

![Version](https://img.shields.io/badge/version-0.2.0-blue) ![Platform](https://img.shields.io/badge/platform-Linux-lightgrey) ![Shell](https://img.shields.io/badge/shell-bash-blue) ![License](https://img.shields.io/badge/license-GPL--3.0-green)

A minimal bash solution to back up Plex Media Server configuration and databases to a NAS. No media files — just the data that's hard to replace.

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
| git | `apt install git` — required to clone the repo |
| rsync | `apt install rsync` — setup.sh will offer to install |
| curl | Required for ntfy alerting — setup.sh will offer to install |
| A backup destination | NFS mount, SMB mount, or local path |

---

## Installation

Clone the repo and run the setup wizard as root or with sudo:

```bash
git clone https://github.com/sfaith/plex-backup
cd plex-backup
sudo bash setup.sh
```

The wizard will:
1. Check for required tools and offer to install any that are missing
2. Walk through all configuration interactively with defaults and examples
3. Configure an NFS mount and fstab entry (if applicable)
4. Write `/etc/plex-backup/plex-backup.conf`
5. Install scripts to `/usr/local/bin/` (or a path of your choosing)
6. Write cron entries to root's crontab

setup.sh is safe to re-run at any time to reconfigure or reinstall.

---

## Configuration

All configuration lives in `/etc/plex-backup/plex-backup.conf`, written by `setup.sh`. You can edit it directly at any time — no need to re-run setup.sh for simple changes.

```bash
sudo nano /etc/plex-backup/plex-backup.conf
```

| Variable | Description | Default |
|---|---|---|
| `PLEX_DATA` | Path to Plex Media Server data directory | `/var/lib/plexmediaserver/Library/Application Support/Plex Media Server` |
| `PLEX_SERVICE` | systemd service name for Plex | `plexmediaserver` |
| `BACKUP_DEST` | Destination path for backup | *(set by setup.sh)* |
| `NFS_EXPORT` | NFS export path — leave blank if not using NFS | `""` |
| `NFS_MOUNT_POINT` | NFS local mount point | `""` |
| `NFS_OPTS` | NFS mount options | `vers=3,soft,...` |
| `LOG_DIR` | Directory for log files | `/var/log/plex-backup` |
| `LOG_RETAIN_DAYS` | Days to keep log files | `7` |
| `WARN_AGE_HOURS` | Warn if backup is older than this many hours | `25` |
| `NTFY_TOPIC` | ntfy topic name — set to `""` to disable | `""` |
| `NTFY_URL` | ntfy server URL | `https://ntfy.sh` |
| `NTFY_ON_FAILURE` | Send alert on backup failure | `true` |
| `NTFY_ON_SUCCESS` | Send alert on backup success | `false` |

---

## Scheduling

setup.sh writes cron entries to root's crontab automatically. To review or modify them:

```bash
sudo crontab -e
```

The default schedule runs the backup at 10:00 UTC (3:00 AM MST) with validation 30 minutes later:

```
0 10 * * * /bin/bash /usr/local/bin/plex-backup.sh
30 10 * * * /bin/bash /usr/local/bin/plex-backup-validate.sh
```

Adjust the UTC hour to match your preferred local time.

---

## Validation

`plex-backup-validate.sh` runs entirely against the NAS copy — Plex is never touched. It checks:

- **NFS mount** — aborts if the backup destination is unreachable
- **Backup age** — warns if the backup is older than `WARN_AGE_HOURS` (catches missed cron runs)
- **Required files** — confirms critical databases and Preferences.xml are present and reports their size
- **Total backup size** — gross sanity check

To run manually:

```bash
sudo /usr/local/bin/plex-backup-validate.sh
```

**Note on SQLite integrity checks:** Plex's main library databases use a proprietary SQLite tokenizer that the system `sqlite3` binary does not support. Integrity checks against these files always fail with `unknown tokenizer: collating` regardless of whether the data is corrupt. This is a Plex limitation, not a script deficiency — the validate script documents this decision in its header comments.

---

## Alerting

Both scripts support [ntfy](https://ntfy.sh) push notifications. Set `NTFY_TOPIC` in `/etc/plex-backup/plex-backup.conf` to enable:

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
- Tautulli backup support — optional, toggled via `TAUTULLI_ENABLED`
