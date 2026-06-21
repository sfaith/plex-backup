# Changelog

All notable changes to PlexBackup are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0/).

---

## [Unreleased]

### Planned
- plex-restore.sh — restore from NAS backup with ownership fix
- plex-backup-validate.sh — SQLite integrity check and backup age validation

---

## [0.1.0] - 2026-06-21

### Added
- Initial release of plex-backup.sh
- Stops Plex Media Server, rsyncs config and databases to NAS, restarts Plex
- Single rolling copy strategy — no dated folders, no retention pruning
- NFS mount check before proceeding — aborts cleanly if mount unavailable
- Plex restarts regardless of rsync exit code
- Excludes Cache, Caches, Crash Reports, Logs, and Plug-in Support/Caches
- Log retention configurable via LOG_RETAIN_DAYS (default: 7 days)
- All user-facing config isolated to top CONFIG block
- .gitignore covering personal config and log files
