#!/usr/bin/env bash
# common.sh - shared helpers sourced by setup.sh, deploy.sh, rollback.sh, cleanup.sh
# Not meant to be executed directly.

# ---- Paths (relative to project root, wherever the calling script lives) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/logs"
BACKUP_DIR="${PROJECT_ROOT}/backups"
CONFIG_DIR="${PROJECT_ROOT}/config"
ENV_FILE="${PROJECT_ROOT}/.env"
STATE_FILE="${PROJECT_ROOT}/.deploy-state.json"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
APP_NAME="xqora-demo-app"
HEALTH_URL_DEFAULT="http://localhost:3000/health"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# ---- Colors ----
if [ -t 1 ]; then
  C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'
  C_BLUE='\033[0;34m'; C_BOLD='\033[1m'; C_RESET='\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''; C_RESET=''
fi

# ---- Logging ----
# Every run gets its own timestamped log file, and a rolling combined log.
RUN_ID="$(date +'%Y%m%d-%H%M%S')"
CURRENT_LOG_FILE="${LOG_DIR}/${1:-run}-${RUN_ID}.log"

log_init() {
  local script_name="$1"
  CURRENT_LOG_FILE="${LOG_DIR}/${script_name}-${RUN_ID}.log"
  touch "$CURRENT_LOG_FILE"
  echo "===== ${script_name} started at $(date -u +'%Y-%m-%dT%H:%M:%SZ') =====" >> "$CURRENT_LOG_FILE"
}

_log() {
  local level="$1"; shift
  local msg="$*"
  local line
  line="[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [${level}] ${msg}"
  echo "$line" >> "$CURRENT_LOG_FILE"
}

log_info()  { _log "INFO"  "$*"; echo -e "${C_BLUE}[INFO]${C_RESET}  $*"; }
log_ok()    { _log "OK"    "$*"; echo -e "${C_GREEN}[ OK ]${C_RESET}  $*"; }
log_warn()  { _log "WARN"  "$*"; echo -e "${C_YELLOW}[WARN]${C_RESET}  $*"; }
log_error() { _log "ERROR" "$*"; echo -e "${C_RED}[FAIL]${C_RESET}  $*" >&2; }
log_step()  { _log "STEP"  "$*"; echo -e "${C_BOLD}==> $*${C_RESET}"; }

# ---- Utility checks ----
command_exists() { command -v "$1" >/dev/null 2>&1; }

require_tool() {
  local tool="$1"
  local hint="$2"
  if command_exists "$tool"; then
    log_ok "Found required tool: ${tool} ($(${tool} --version 2>&1 | head -n1))"
    return 0
  else
    log_error "Missing required tool: ${tool}. ${hint}"
    return 1
  fi
}

port_in_use() {
  local port="$1"
  if command_exists lsof; then
    lsof -i ":${port}" >/dev/null 2>&1
  elif command_exists netstat; then
    netstat -tuln 2>/dev/null | grep -q ":${port} "
  else
    # Fall back to a raw /dev/tcp probe
    (echo > "/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1
  fi
}

docker_compose_cmd() {
  # Prefer the modern "docker compose" plugin, fall back to docker-compose
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command_exists docker-compose; then
    echo "docker-compose"
  else
    echo ""
  fi
}

# ---- Simple JSON state file (deployment version, status, history) ----
state_write() {
  local status="$1" version="$2" reason="$3"
  cat > "$STATE_FILE" <<EOF
{
  "status": "${status}",
  "version": "${version}",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "reason": "${reason}"
}
EOF
}

state_read_field() {
  local field="$1"
  [ -f "$STATE_FILE" ] || { echo ""; return; }
  grep -o "\"${field}\": *\"[^\"]*\"" "$STATE_FILE" | sed -E "s/\"${field}\": *\"([^\"]*)\"/\1/"
}
