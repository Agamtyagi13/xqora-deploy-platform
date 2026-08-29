#!/usr/bin/env bash
# setup.sh
# Automated environment setup for the XQORA one-click deployment platform.
#
# Responsibilities:
#   1. Check whether required tools are installed (docker, docker compose, curl/wget)
#   2. Validate Docker installation (daemon reachable)
#   3. Check that the target port is available
#   4. Create required directories (logs, backups, config)
#   5. Generate environment configuration files (.env)
#   6. Prepare the deployment environment (pull/verify base image, network)
#
# Displays a clear message for each missing requirement and exits non-zero
# if the environment is not ready for deployment.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"
log_init "setup"

MISSING=0
HOST_PORT="${HOST_PORT:-3000}"

log_step "1/6  Checking required tools"
require_tool docker    "Install Docker: https://docs.docker.com/get-docker/"        || MISSING=1
if [ -n "$(docker_compose_cmd 2>/dev/null)" ]; then
  log_ok "Found Docker Compose ($(docker_compose_cmd))"
else
  log_error "Missing Docker Compose plugin/binary. Install via 'docker compose' plugin or docker-compose."
  MISSING=1
fi
if command_exists curl || command_exists wget; then
  log_ok "Found HTTP client (curl/wget) for health checks"
else
  log_error "Neither curl nor wget found - required for health checks."
  MISSING=1
fi

log_step "2/6  Validating Docker installation"
if command_exists docker; then
  if docker info >/dev/null 2>&1; then
    log_ok "Docker daemon is running and reachable"
  else
    log_error "Docker is installed but the daemon is not reachable. Is Docker running / do you have permission (docker group)?"
    MISSING=1
  fi
fi

log_step "3/6  Checking available ports"
if port_in_use "$HOST_PORT"; then
  log_warn "Port ${HOST_PORT} is currently in use."
  ALT_PORT=$((HOST_PORT + 1))
  while port_in_use "$ALT_PORT"; do
    ALT_PORT=$((ALT_PORT + 1))
  done
  log_warn "Falling back to free port ${ALT_PORT}. Set HOST_PORT to override."
  HOST_PORT="$ALT_PORT"
else
  log_ok "Port ${HOST_PORT} is available"
fi

log_step "4/6  Creating required directories"
for d in "$LOG_DIR" "$BACKUP_DIR" "$CONFIG_DIR"; do
  mkdir -p "$d" && log_ok "Directory ready: ${d}"
done

log_step "5/6  Generating environment configuration"
APP_VERSION="${APP_VERSION:-1.0.0}"
cat > "$ENV_FILE" <<EOF
APP_VERSION=${APP_VERSION}
HOST_PORT=${HOST_PORT}
PROJECT_NAME=${APP_NAME}
EOF
log_ok "Wrote configuration to ${ENV_FILE} (APP_VERSION=${APP_VERSION}, HOST_PORT=${HOST_PORT})"

log_step "6/6  Preparing deployment environment"
if [ ! -f "$COMPOSE_FILE" ]; then
  log_error "docker-compose.yml not found at ${COMPOSE_FILE}"
  MISSING=1
else
  log_ok "Found docker-compose.yml"
fi
if [ ! -f "${PROJECT_ROOT}/app/Dockerfile" ]; then
  log_error "Dockerfile not found at ${PROJECT_ROOT}/app/Dockerfile"
  MISSING=1
else
  log_ok "Found application Dockerfile"
fi

echo ""
if [ "$MISSING" -eq 0 ]; then
  log_ok "Environment setup complete. Ready to deploy."
  echo -e "${C_GREEN}${C_BOLD}ENVIRONMENT READY${C_RESET}"
  exit 0
else
  log_error "One or more requirements are missing. See messages above."
  echo -e "${C_RED}${C_BOLD}ENVIRONMENT NOT READY${C_RESET}"
  exit 1
fi
