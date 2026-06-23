#!/usr/bin/env bash
# =============================================================================
# setup.sh — plex-backup Setup Wizard
# =============================================================================
#
# Interactive setup wizard for plex-backup.
# Run from the cloned repo directory as root or with sudo.
#
# Steps:
#   1. Prerequisites
#   2. Configuration
#   3. NFS mount setup (if applicable)
#   4. Write /etc/plex-backup/plex-backup.conf
#   5. Install scripts
#   6. Cron setup
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="/etc/plex-backup"
CONF_FILE="${CONF_DIR}/plex-backup.conf"
BACKUP_EXAMPLE="${SCRIPT_DIR}/plex-backup.sh.example"
VALIDATE_EXAMPLE="${SCRIPT_DIR}/plex-backup-validate.sh.example"
LOG_FILE="/var/log/plex-backup-setup.log"

mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
info()    { echo -e "\n\e[1;34m[INFO]\e[0m  $*"; }
success() { echo -e "\e[1;32m[OK]\e[0m    $*"; }
warn()    { echo -e "\e[1;33m[WARN]\e[0m  $*"; }
error()   { echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

prompt() {
  local var="$1" label="$2" current="$3" placeholder="${4:-}"
  local input
  echo -en "\n  ${label}"
  if [[ -n "${current}" ]]; then
    echo -en " \e[2m[${current}]\e[0m (press Enter to accept): "
  elif [[ -n "${placeholder}" ]]; then
    echo -en " \e[2m(e.g. ${placeholder})\e[0m: "
  else
    echo -en ": "
  fi
  read -r input
  if [[ -n "${input}" ]]; then
    printf -v "${var}" '%s' "${input}"
  else
    printf -v "${var}" '%s' "${current}"
  fi
}

menu() {
  local var="$1" default="$2"
  shift 2
  local i=1
  for opt in "$@"; do
    if [[ "${i}" == "${default}" ]]; then
      echo "    ${i}) ${opt}  ← default"
    else
      echo "    ${i}) ${opt}"
    fi
    i=$(( i + 1 ))
  done
  local answer
  echo -en "\n  Choice [${default}]: "
  read -r answer
  [[ -z "${answer}" ]] && answer="${default}"
  printf -v "${var}" '%s' "${answer}"
}

confirm() {
  local answer
  echo -en "\n  $* [y/N]: "
  read -r answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
echo
echo "============================================================"
echo "  plex-backup — Setup Wizard"
echo "  github.com/sfaith/plex-backup"
echo "============================================================"
echo
echo "  This wizard will:"
echo "    1. Check prerequisites"
echo "    2. Walk through your configuration"
echo "    3. Set up NFS mount (if applicable)"
echo "    4. Write /etc/plex-backup/plex-backup.conf"
echo "    5. Install scripts"
echo "    6. Configure cron"
echo
echo "  Setup output is being logged to:"
echo "    ${LOG_FILE}"
echo
echo "  Press Ctrl+C at any time to abort."

# -----------------------------------------------------------------------------
# Step 0 — Root check
# -----------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  error "This script must be run as root or with sudo."
fi

# -----------------------------------------------------------------------------
# Step 1 — Prerequisites
# -----------------------------------------------------------------------------
info "Step 1/6 — Prerequisites"

MISSING_TOOLS=()
for tool in rsync curl; do
  if command -v "${tool}" &>/dev/null; then
    success "${tool} found."
  else
    warn "${tool} not found."
    MISSING_TOOLS+=("${tool}")
  fi
done

if [[ "${#MISSING_TOOLS[@]}" -gt 0 ]]; then
  echo
  echo "  Missing tools: ${MISSING_TOOLS[*]}"
  if confirm "Attempt to install missing tools with apt?"; then
    apt-get update -qq
    apt-get install -y "${MISSING_TOOLS[@]}"
    success "Tools installed."
  else
    error "Required tools are missing. Install them and re-run setup.sh."
  fi
fi

if [[ ! -f "${BACKUP_EXAMPLE}" ]]; then
  error "Missing: ${BACKUP_EXAMPLE} — run setup.sh from the repo directory."
fi
if [[ ! -f "${VALIDATE_EXAMPLE}" ]]; then
  error "Missing: ${VALIDATE_EXAMPLE} — run setup.sh from the repo directory."
fi
success "Example scripts found."

# -----------------------------------------------------------------------------
# Default CFG_* values — overridden by existing conf or user input
# -----------------------------------------------------------------------------
CFG_PLEX_DATA="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server"
CFG_PLEX_SERVICE="plexmediaserver"
CFG_NFS_EXPORT=""
CFG_NFS_MOUNT_POINT=""
CFG_NFS_OPTS="vers=3,soft,rsize=131072,wsize=131072,timeo=600,retrans=2,_netdev"
CFG_BACKUP_DEST=""
CFG_LOG_DIR="/var/log/plex-backup"
CFG_LOG_RETAIN_DAYS="7"
CFG_WARN_AGE_HOURS="25"
CFG_NTFY_TOPIC=""
CFG_NTFY_URL="https://ntfy.sh"
CFG_NTFY_ON_FAILURE="true"
CFG_NTFY_ON_SUCCESS="false"
CFG_TAUTULLI_ENABLED="false"
CFG_TAUTULLI_DATA="/opt/Tautulli"
CFG_TAUTULLI_BACKUP_DEST=""

# -----------------------------------------------------------------------------
# Section functions — each prompts only its own variables
# -----------------------------------------------------------------------------
configure_plex() {
  echo
  echo "  Press Enter to accept each default value shown in [brackets]."
  prompt CFG_PLEX_DATA    "Plex data directory  " "${CFG_PLEX_DATA}"
  if [[ -d "${CFG_PLEX_DATA}" ]]; then
    success "Directory exists."
  else
    warn "Directory not found — verify the path before continuing."
  fi
  prompt CFG_PLEX_SERVICE "Plex systemd service " "${CFG_PLEX_SERVICE}"
  if systemctl is-active --quiet "${CFG_PLEX_SERVICE}" 2>/dev/null || \
     systemctl is-enabled --quiet "${CFG_PLEX_SERVICE}" 2>/dev/null; then
    success "Service '${CFG_PLEX_SERVICE}' found."
  else
    warn "Service '${CFG_PLEX_SERVICE}' not detected — verify with: systemctl list-units --type=service | grep -i plex"
  fi
}

configure_nfs() {
  echo
  if confirm "Is your backup destination on an NFS share?"; then
    if ! command -v mount.nfs &>/dev/null; then
      warn "mount.nfs not found — NFS support requires the nfs-common package."
      if confirm "Attempt to install nfs-common with apt?"; then
        apt-get update -qq
        apt-get install -y nfs-common
        success "nfs-common installed."
      else
        error "nfs-common is required for NFS mounts. Install it and re-run setup.sh."
      fi
    else
      success "mount.nfs found."
    fi
    while [[ -z "${CFG_NFS_EXPORT}" ]]; do
      prompt CFG_NFS_EXPORT      "NFS export         " "${CFG_NFS_EXPORT}"      "192.168.1.93:/volume1/Backups"
      if [[ -z "${CFG_NFS_EXPORT}" ]]; then warn "NFS export is required."; fi
    done
    while [[ -z "${CFG_NFS_MOUNT_POINT}" ]]; do
      prompt CFG_NFS_MOUNT_POINT "NFS mount point    " "${CFG_NFS_MOUNT_POINT}" "/mnt/nfs/nas03/backups"
      if [[ -z "${CFG_NFS_MOUNT_POINT}" ]]; then warn "NFS mount point is required."; fi
    done
    prompt CFG_NFS_OPTS    "NFS mount options  " "${CFG_NFS_OPTS}"
    local default_dest="${CFG_NFS_MOUNT_POINT}/Plex"
    [[ -z "${CFG_BACKUP_DEST}" ]] && CFG_BACKUP_DEST="${default_dest}"
    prompt CFG_BACKUP_DEST "Backup destination " "${CFG_BACKUP_DEST}"
  else
    CFG_NFS_EXPORT=""
    CFG_NFS_MOUNT_POINT=""
    prompt CFG_BACKUP_DEST "Backup destination " "${CFG_BACKUP_DEST}" "/mnt/backups/Plex"
  fi
  if [[ -z "${CFG_BACKUP_DEST}" ]]; then
    error "Backup destination is required."
  fi
}

configure_logging() {
  echo
  prompt CFG_LOG_DIR         "Log directory      " "${CFG_LOG_DIR}"
  prompt CFG_LOG_RETAIN_DAYS "Log retention days " "${CFG_LOG_RETAIN_DAYS}"
  prompt CFG_WARN_AGE_HOURS  "Backup age warning " "${CFG_WARN_AGE_HOURS}"
}

configure_ntfy() {
  echo
  if confirm "Configure ntfy alerting?"; then
    prompt CFG_NTFY_TOPIC "ntfy topic         " "${CFG_NTFY_TOPIC}" "my-plex-backup"
    prompt CFG_NTFY_URL   "ntfy server URL    " "${CFG_NTFY_URL}"
    if [[ -z "${CFG_NTFY_TOPIC}" ]]; then
      error "ntfy topic is required when alerting is enabled."
    fi
    echo
    menu CFG_NTFY_ON_FAILURE 1 "Alert on failure (recommended)" "No failure alerts"
    if [[ "${CFG_NTFY_ON_FAILURE}" == "1" ]]; then CFG_NTFY_ON_FAILURE="true"; else CFG_NTFY_ON_FAILURE="false"; fi
    echo
    menu CFG_NTFY_ON_SUCCESS 2 "Alert on success" "No success alerts (recommended)"
    if [[ "${CFG_NTFY_ON_SUCCESS}" == "1" ]]; then CFG_NTFY_ON_SUCCESS="true"; else CFG_NTFY_ON_SUCCESS="false"; fi
  else
    CFG_NTFY_TOPIC=""
  fi
}

configure_tautulli() {
  echo
  if confirm "Back up Tautulli?"; then
    CFG_TAUTULLI_ENABLED="true"
    prompt CFG_TAUTULLI_DATA "Tautulli directory " "${CFG_TAUTULLI_DATA}"
    if [[ -d "${CFG_TAUTULLI_DATA}" ]]; then
      success "Directory exists."
    else
      warn "Directory not found — verify the path before continuing."
    fi
    if [[ -n "${CFG_NFS_MOUNT_POINT}" && -z "${CFG_TAUTULLI_BACKUP_DEST}" ]]; then
      CFG_TAUTULLI_BACKUP_DEST="${CFG_NFS_MOUNT_POINT}/Tautulli"
    fi
    prompt CFG_TAUTULLI_BACKUP_DEST "Tautulli backup    " "${CFG_TAUTULLI_BACKUP_DEST}" "/mnt/nfs/nas03/backups/Tautulli"
    if [[ -z "${CFG_TAUTULLI_BACKUP_DEST}" ]]; then
      error "Tautulli backup destination is required."
    fi
  else
    CFG_TAUTULLI_ENABLED="false"
  fi
}

# -----------------------------------------------------------------------------
# Step 2 — Configuration
# -----------------------------------------------------------------------------
info "Step 2/6 — Configuration"

SETUP_MODE="full"

if [[ -f "${CONF_FILE}" ]]; then
  echo
  echo "  Existing configuration found at ${CONF_FILE}"
  echo
  echo "    1) Reinstall scripts as-is (skip configuration)"
  echo "    2) Update a section"
  echo "    3) Full reconfigure"
  echo
  echo -en "  Choice [1]: "
  read -r MODE_CHOICE
  [[ -z "${MODE_CHOICE}" ]] && MODE_CHOICE="1"

  # Source existing conf into CFG_* variables
  # shellcheck source=/dev/null
  source "${CONF_FILE}"
  CFG_PLEX_DATA="${PLEX_DATA:-${CFG_PLEX_DATA}}"
  CFG_PLEX_SERVICE="${PLEX_SERVICE:-${CFG_PLEX_SERVICE}}"
  CFG_NFS_EXPORT="${NFS_EXPORT:-${CFG_NFS_EXPORT}}"
  CFG_NFS_MOUNT_POINT="${NFS_MOUNT_POINT:-${CFG_NFS_MOUNT_POINT}}"
  CFG_NFS_OPTS="${NFS_OPTS:-${CFG_NFS_OPTS}}"
  CFG_BACKUP_DEST="${BACKUP_DEST:-${CFG_BACKUP_DEST}}"
  CFG_LOG_DIR="${LOG_DIR:-${CFG_LOG_DIR}}"
  CFG_LOG_RETAIN_DAYS="${LOG_RETAIN_DAYS:-${CFG_LOG_RETAIN_DAYS}}"
  CFG_WARN_AGE_HOURS="${WARN_AGE_HOURS:-${CFG_WARN_AGE_HOURS}}"
  CFG_NTFY_TOPIC="${NTFY_TOPIC:-${CFG_NTFY_TOPIC}}"
  CFG_NTFY_URL="${NTFY_URL:-${CFG_NTFY_URL}}"
  CFG_NTFY_ON_FAILURE="${NTFY_ON_FAILURE:-${CFG_NTFY_ON_FAILURE}}"
  CFG_NTFY_ON_SUCCESS="${NTFY_ON_SUCCESS:-${CFG_NTFY_ON_SUCCESS}}"
  CFG_TAUTULLI_ENABLED="${TAUTULLI_ENABLED:-${CFG_TAUTULLI_ENABLED}}"
  CFG_TAUTULLI_DATA="${TAUTULLI_DATA:-${CFG_TAUTULLI_DATA}}"
  CFG_TAUTULLI_BACKUP_DEST="${TAUTULLI_BACKUP_DEST:-${CFG_TAUTULLI_BACKUP_DEST}}"

  case "${MODE_CHOICE}" in
    1) SETUP_MODE="reinstall" ;;
    2) SETUP_MODE="update" ;;
    3) SETUP_MODE="full" ;;
    *) warn "Invalid choice — defaulting to reinstall." ; SETUP_MODE="reinstall" ;;
  esac
fi

case "${SETUP_MODE}" in
  reinstall)
    echo
    echo "  Skipping configuration — using existing settings."
    ;;
  update)
    echo
    echo "  Select sections to update."
    echo "  Enter numbers separated by spaces, then Enter."
    echo
    echo "    1) Plex settings"
    echo "    2) NFS / backup destination"
    echo "    3) Logging"
    echo "    4) ntfy alerting"
    echo "    5) Tautulli"
    echo
    echo -en "  Sections to update: "
    read -r SECTION_INPUT
    if ! [[ "${SECTION_INPUT}" =~ ^[1-5\ ]+$ ]]; then
      warn "Invalid input — no sections updated."
      SECTION_INPUT=""
    fi
    echo
    for sec in ${SECTION_INPUT}; do
      case "${sec}" in
        1) echo "  — Plex settings" ;             configure_plex ;;
        2) echo "  — NFS / backup destination" ;  configure_nfs ;;
        3) echo "  — Logging" ;                   configure_logging ;;
        4) echo "  — ntfy alerting" ;             configure_ntfy ;;
        5) echo "  — Tautulli" ;                  configure_tautulli ;;
      esac
    done
    ;;
  full)
    configure_plex
    configure_nfs
    configure_logging
    configure_ntfy
    configure_tautulli
    ;;
esac

# -----------------------------------------------------------------------------
# Step 3 — NFS mount setup
# -----------------------------------------------------------------------------
info "Step 3/6 — NFS mount setup"

if [[ -n "${CFG_NFS_EXPORT}" ]]; then
  # Create mount point
  if [[ ! -d "${CFG_NFS_MOUNT_POINT}" ]]; then
    if confirm "Create mount point ${CFG_NFS_MOUNT_POINT}?"; then
      mkdir -p "${CFG_NFS_MOUNT_POINT}"
      success "Mount point created."
    else
      error "Mount point is required. Aborting."
    fi
  else
    success "Mount point already exists: ${CFG_NFS_MOUNT_POINT}"
  fi

  # fstab
  FSTAB_ENTRY="${CFG_NFS_EXPORT} ${CFG_NFS_MOUNT_POINT} nfs ${CFG_NFS_OPTS} 0 0"
  if grep -qsF "${CFG_NFS_EXPORT}" /etc/fstab; then
    success "fstab entry already present for ${CFG_NFS_EXPORT}."
  else
    echo
    echo "  The following line will be added to /etc/fstab:"
    echo
    echo "    ${FSTAB_ENTRY}"
    echo
    if confirm "Write this entry to /etc/fstab?"; then
      echo "${FSTAB_ENTRY}" >> /etc/fstab
      success "fstab entry written."
    else
      warn "Skipping fstab write — mount will not persist across reboots."
    fi
  fi

  # Mount now
  if mountpoint -q "${CFG_NFS_MOUNT_POINT}"; then
    success "NFS share already mounted."
  else
    if confirm "Mount NFS share now?"; then
      mount "${CFG_NFS_MOUNT_POINT}"
      mountpoint -q "${CFG_NFS_MOUNT_POINT}" \
        && success "NFS share mounted successfully." \
        || error "Mount failed — check NFS export and network connectivity."
    else
      warn "Skipping mount — share must be mounted before running backups."
    fi
  fi

  # Create backup subdirectory
  if [[ ! -d "${CFG_BACKUP_DEST}" ]]; then
    if confirm "Create backup destination ${CFG_BACKUP_DEST}?"; then
      mkdir -p "${CFG_BACKUP_DEST}"
      success "Backup destination created."
    fi
  else
    success "Backup destination already exists: ${CFG_BACKUP_DEST}"
  fi

  # Create Tautulli backup subdirectory if enabled
  if [[ "${CFG_TAUTULLI_ENABLED}" == "true" && -n "${CFG_TAUTULLI_BACKUP_DEST}" ]]; then
    if [[ ! -d "${CFG_TAUTULLI_BACKUP_DEST}" ]]; then
      if confirm "Create Tautulli backup destination ${CFG_TAUTULLI_BACKUP_DEST}?"; then
        mkdir -p "${CFG_TAUTULLI_BACKUP_DEST}"
        success "Tautulli backup destination created."
      fi
    else
      success "Tautulli backup destination already exists: ${CFG_TAUTULLI_BACKUP_DEST}"
    fi
  fi
else
  info "NFS not configured — skipping."
fi

# -----------------------------------------------------------------------------
# Step 4 — Write config file
# -----------------------------------------------------------------------------
info "Step 4/6 — Writing configuration"

mkdir -p "${CONF_DIR}"

cat > "${CONF_FILE}" <<EOF
# plex-backup.conf — Configuration for plex-backup scripts
# Generated by setup.sh on $(date)
# Location: ${CONF_FILE}
# Permissions: chmod 600, chown root:root

# =============================================================================
# Plex Media Server
# =============================================================================
PLEX_DATA="${CFG_PLEX_DATA}"
PLEX_SERVICE="${CFG_PLEX_SERVICE}"

# =============================================================================
# Backup destination
# =============================================================================
BACKUP_DEST="${CFG_BACKUP_DEST}"

# =============================================================================
# NFS mount (optional)
# =============================================================================
NFS_EXPORT="${CFG_NFS_EXPORT}"
NFS_MOUNT_POINT="${CFG_NFS_MOUNT_POINT}"
NFS_OPTS="${CFG_NFS_OPTS}"

# =============================================================================
# Logging
# =============================================================================
LOG_DIR="${CFG_LOG_DIR}"
LOG_RETAIN_DAYS=${CFG_LOG_RETAIN_DAYS}

# =============================================================================
# Validation
# =============================================================================
WARN_AGE_HOURS=${CFG_WARN_AGE_HOURS}

# =============================================================================
# ntfy alerting
# =============================================================================
NTFY_TOPIC="${CFG_NTFY_TOPIC}"
NTFY_URL="${CFG_NTFY_URL}"
NTFY_ON_FAILURE=${CFG_NTFY_ON_FAILURE}
NTFY_ON_SUCCESS=${CFG_NTFY_ON_SUCCESS}

# =============================================================================
# Tautulli
# =============================================================================
TAUTULLI_ENABLED=${CFG_TAUTULLI_ENABLED}
TAUTULLI_DATA="${CFG_TAUTULLI_DATA}"
TAUTULLI_BACKUP_DEST="${CFG_TAUTULLI_BACKUP_DEST}"
EOF

chmod 600 "${CONF_FILE}"
chown root:root "${CONF_FILE}"
success "Config written to ${CONF_FILE}"

# -----------------------------------------------------------------------------
# Step 5 — Install scripts
# -----------------------------------------------------------------------------
info "Step 5/6 — Script installation"

CFG_INSTALL_PATH="/usr/local/bin"

if [[ "${SETUP_MODE}" == "reinstall" ]]; then
  INSTALL_BACKUP="${CFG_INSTALL_PATH}/plex-backup.sh"
  INSTALL_VALIDATE="${CFG_INSTALL_PATH}/plex-backup-validate.sh"
  cp "${BACKUP_EXAMPLE}"   "${INSTALL_BACKUP}"
  cp "${VALIDATE_EXAMPLE}" "${INSTALL_VALIDATE}"
  chmod 700 "${INSTALL_BACKUP}" "${INSTALL_VALIDATE}"
  chown root:root "${INSTALL_BACKUP}" "${INSTALL_VALIDATE}"
  success "Scripts reinstalled to ${CFG_INSTALL_PATH}."
else
  prompt CFG_INSTALL_PATH "Install path       " "${CFG_INSTALL_PATH}"

  INSTALL_BACKUP="${CFG_INSTALL_PATH}/plex-backup.sh"
  INSTALL_VALIDATE="${CFG_INSTALL_PATH}/plex-backup-validate.sh"

  for target in "${INSTALL_BACKUP}" "${INSTALL_VALIDATE}"; do
    if [[ -f "${target}" ]]; then
      warn "Existing script found: ${target}"
      confirm "Overwrite?" || error "Aborting — remove existing scripts or choose a different install path."
    fi
  done

  cp "${BACKUP_EXAMPLE}"   "${INSTALL_BACKUP}"
  cp "${VALIDATE_EXAMPLE}" "${INSTALL_VALIDATE}"
  chmod 700 "${INSTALL_BACKUP}" "${INSTALL_VALIDATE}"
  chown root:root "${INSTALL_BACKUP}" "${INSTALL_VALIDATE}"
  success "Scripts installed to ${CFG_INSTALL_PATH}."
fi

# -----------------------------------------------------------------------------
# Step 6 — Cron setup
# -----------------------------------------------------------------------------
info "Step 6/6 — Cron configuration"

echo
echo "  Cron entries run as root (scripts require systemctl stop/start)."
echo "  Enter your desired backup time in UTC."
echo "  Example: 3:00 AM MST (UTC-7) = 10:00 UTC."
echo
echo "  Note: Validation runs automatically at the end of each backup run."
echo "  No separate validation cron entry is needed."
echo

CFG_CRON_UTC="10:00"

# Carry forward existing cron time if a plex-backup entry already exists
EXISTING_CRON_CHECK=$(crontab -u root -l 2>/dev/null || true)
if echo "${EXISTING_CRON_CHECK}" | grep -q "plex-backup"; then
  EXISTING_ENTRY=$(echo "${EXISTING_CRON_CHECK}" | grep "plex-backup" | head -1)
  EXISTING_M=$(echo "${EXISTING_ENTRY}" | awk '{print $1}')
  EXISTING_H=$(echo "${EXISTING_ENTRY}" | awk '{print $2}')
  if [[ "${EXISTING_H}" =~ ^[0-9]+$ && "${EXISTING_M}" =~ ^[0-9]+$ ]]; then
    CFG_CRON_UTC=$(printf "%02d:%02d" "${EXISTING_H}" "${EXISTING_M}")
  fi
fi

prompt CFG_CRON_UTC "Backup time (UTC)  " "${CFG_CRON_UTC}"
if ! [[ "${CFG_CRON_UTC}" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  warn "Invalid time format — defaulting to 10:00."
  CFG_CRON_UTC="10:00"
fi

CRON_H="${CFG_CRON_UTC%%:*}"
CRON_M="${CFG_CRON_UTC##*:}"
CRON_BACKUP="${CRON_M} ${CRON_H} * * * /bin/bash ${INSTALL_BACKUP}"

echo
echo "  The following cron entry will be written for root:"
echo
echo "    ${CRON_BACKUP}"
echo

SKIP_CRON=false
EXISTING_CRON=$(crontab -u root -l 2>/dev/null || true)

if echo "${EXISTING_CRON}" | grep -q "plex-backup"; then
  warn "Existing plex-backup cron entries found:"
  echo "${EXISTING_CRON}" | grep "plex-backup" | sed 's/^/    /'
  echo
  echo "  Will be replaced with:"
  echo
  echo "    ${CRON_BACKUP}"
  echo
  if confirm "Replace existing plex-backup cron entries?"; then
    CLEAN_CRON=$(echo "${EXISTING_CRON}" | grep -v "plex-backup" || true)
    {
      [[ -n "${CLEAN_CRON}" ]] && echo "${CLEAN_CRON}"
      echo "${CRON_BACKUP}"
    } | crontab -u root -
    success "Cron entry written."
  else
    SKIP_CRON=true
    warn "Skipping cron — existing entries unchanged."
  fi
else
  if confirm "Write this cron entry?"; then
    CLEAN_CRON=$(echo "${EXISTING_CRON}" | grep -v "plex-backup" || true)
    {
      [[ -n "${CLEAN_CRON}" ]] && echo "${CLEAN_CRON}"
      echo "${CRON_BACKUP}"
    } | crontab -u root -
    success "Cron entry written."
  else
    SKIP_CRON=true
    warn "Skipping cron — add entry manually with: crontab -e"
  fi
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo
echo "============================================================"
echo "  plex-backup setup complete."
echo "============================================================"
echo
echo "  Config:    ${CONF_FILE}"
echo "  Scripts:   ${INSTALL_BACKUP}"
echo "             ${INSTALL_VALIDATE}"
echo "  Logs:      ${CFG_LOG_DIR}/"
echo "  Setup log: ${LOG_FILE}"
echo
echo "  To run an initial backup (first run may take several hours):"
echo "    sudo ${INSTALL_BACKUP}"
echo
echo "  Validation runs automatically at the end of each backup."
echo "  To validate manually:"
echo "    sudo ${INSTALL_VALIDATE}"
echo
success "Done."
