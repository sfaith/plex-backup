# Changelog

All notable changes to plex-backup are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0/).

---

## [Unreleased]

### Planned
- plex-restore.sh — restore from NAS backup with ownership fix
- plex-backup.conf — shared config file sourced by all scripts
- Tautulli backup support (optional, toggled via TAUTULLI_ENABLED)

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
