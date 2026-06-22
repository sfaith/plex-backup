# Changelog

All notable changes to plex-backup are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0/).

---

## [Unreleased]

### Planned
- plex-restore.sh — restore from NAS backup with ownership fix

---

## [0.3.6] - 2026-06-21

### Changed
- plex-backup.sh now excludes `Plug-in Support/Databases/dbtmp/` from rsync — this directory is used by Plex for temporary DB repair and export files and should never be backed up

---

## [0.3.5] - 2026-06-21

### Changed
- setup.sh completion screen now distinguishes the initial backup command from the manual validation command, and notes that the first backup may take several hours

---

## [0.3.4] - 2026-06-21

### Changed
- setup.sh reinstall mode now skips the install path prompt and overwrite confirmations — scripts are replaced silently with a single [OK] line

---

## [0.3.3] - 2026-06-21

### Changed
- setup.sh cron step now shows both the existing and replacement entry side-by-side before prompting; the redundant second confirmation is removed when replacing an existing entry

---

## [0.3.2] - 2026-06-21

### Changed
- setup.sh now detects an existing conf file and offers three modes: reinstall as-is (skip all prompts), update a specific section, or full reconfigure
- In update mode, a numbered section selector lets you reprompt only the sections you need; all other values carry forward from the existing conf
- In all modes, existing conf values are loaded as defaults so prompts pre-populate with current settings

---

## [0.3.1] - 2026-06-21

### Changed
- plex-backup.sh now waits up to 30 seconds for Plex to confirm active after restart, mirroring stop logic; logs `plexmediaserver started after Xs` on success or exits non-zero with an ntfy alert if it fails to come up

---

## [0.3.0] - 2026-06-21

### Added
- Tautulli backup support — optional, enabled via `TAUTULLI_ENABLED=true` in conf; backs up `tautulli.db`, `config.ini`, `config.bak`, and `data/` to a configurable destination
- Tautulli validation in plex-backup-validate.sh — checks required files and reports total size when `TAUTULLI_ENABLED=true`
- Tautulli configuration prompts in setup.sh — wizard creates backup destination directory and updates conf automatically

### Changed
- plex-backup.sh now calls plex-backup-validate.sh automatically at the end of a successful run — no separate cron entry needed
- plex-backup.sh now exits non-zero if Plex fails to restart after backup
- setup.sh cron step writes a single backup entry and removes any existing standalone validate cron entry

---

## [0.2.0] - 2026-06-21

### Added
- setup.sh — interactive setup wizard covering prerequisites, configuration, NFS mount, script install, and cron setup
- plex-backup.conf.example — shared configuration file for all scripts

### Changed
- plex-backup.sh.example — refactored to source /etc/plex-backup/plex-backup.conf instead of embedding config block
- plex-backup-validate.sh.example — refactored to source /etc/plex-backup/plex-backup.conf; renamed BACKUP_ROOT to BACKUP_DEST for consistency; added set -euo pipefail
- Both scripts now abort with a clear message if conf file is not found

---

## [0.1.0] - 2026-06-21

### Added
- plex-backup.sh — stops Plex, rsyncs config and databases to NAS, restarts Plex
- plex-backup-validate.sh — validates backup age, required files, and total size
- ntfy.sh alerting support in both scripts (NTFY_ON_FAILURE, NTFY_ON_SUCCESS toggles)
- Single rolling copy strategy — no dated folders, no retention pruning
- NFS mount check before proceeding — aborts cleanly if mount unavailable
- Plex restarts regardless of rsync exit code
- Excludes Cache, Caches, Crash Reports, Logs, and Plug-in Support/Caches
- Log retention configurable via LOG_RETAIN_DAYS (default: 7 days)
- All user-facing config isolated to top CONFIG block in each script
- Documented why SQLite integrity checks and file hashing were omitted
- .gitignore covering personal config and log files
