#!/usr/bin/env bash
# cleanup.sh
# Environment cleanup tool for the XQORA deployment platform.
#
# Usage:
#   ./scripts/cleanup.sh            # normal cleanup
#   ./scripts/cleanup.sh --all      # also remove the 'last-good' image (deeper clean)
#
# Steps:
#   1. Stop project containers
#   2. Remove unused project images
#   3. Remove temporary files
#   4. Clear unnecessary logs (keeps the most recent N logs)
#   5. Preserve important configuration and backup files (.env, backups/, state file)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
log_init "cleanup"

DEEP_CLEAN=0
[ "${1:-}" = "--all" ] && DEEP_CLEAN=1

KEEP_LOGS=10   # how many recent log files per script to preserve
COMPOSE="$(docker_compose_cmd)"

log_step "1/5  Stopping project containers"
if [ -n "$COMPOSE" ] && [ -f "$COMPOSE_FILE" ]; then
  cd "$PROJECT_ROOT" || true
  $COMPOSE down >>"$CURRENT_LOG_FILE" 2>&1 && log_ok "Containers stopped and removed via docker compose down"
else
  if docker ps -a --format '{{.Names}}' | grep -q "^${APP_NAME}$"; then
    docker rm -f "$APP_NAME" >>"$CURRENT_LOG_FILE" 2>&1
    log_ok "Removed container: ${APP_NAME}"
  else
    log_info "No running/existing container named ${APP_NAME} found"
  fi
fi

log_step "2/5  Removing unused project images"
# Never remove the 'last-good' tag unless --all is passed - it's needed for rollback safety net.
DANGLING="$(docker images -f "dangling=true" -q)"
if [ -n "$DANGLING" ]; then
  echo "$DANGLING" | xargs -r docker rmi >>"$CURRENT_LOG_FILE" 2>&1
  log_ok "Removed dangling (untagged) images"
else
  log_info "No dangling images to remove"
fi

if [ "$DEEP_CLEAN" -eq 1 ]; then
  log_warn "--all specified: removing '${APP_NAME}:last-good' rollback image too"
  docker rmi "${APP_NAME}:last-good" >>"$CURRENT_LOG_FILE" 2>&1 || true
else
  log_info "Preserving '${APP_NAME}:last-good' image (rollback safety net). Use --all to remove it."
fi

log_step "3/5  Removing temporary files"
find "$PROJECT_ROOT" -name "*.tmp" -type f -print -delete >>"$CURRENT_LOG_FILE" 2>&1
find "$PROJECT_ROOT" -name "*.pid" -type f -print -delete >>"$CURRENT_LOG_FILE" 2>&1
log_ok "Removed *.tmp and *.pid files (if any)"

log_step "4/5  Clearing unnecessary logs"
for prefix in setup deploy rollback cleanup; do
  # shellcheck disable=SC2012
  ls -1t "${LOG_DIR}/${prefix}-"*.log 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | xargs -r rm -f
done
ls -1t "${LOG_DIR}/deployment-report-"*.txt 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | xargs -r rm -f
ls -1t "${LOG_DIR}/rollback-report-"*.txt 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | xargs -r rm -f
log_ok "Trimmed old log/report files, kept the most recent ${KEEP_LOGS} per type"

log_step "5/5  Preserving important configuration and backup files"
[ -f "$ENV_FILE" ] && log_ok "Preserved: ${ENV_FILE}"
[ -d "$BACKUP_DIR" ] && log_ok "Preserved backups directory: ${BACKUP_DIR}"
[ -f "$STATE_FILE" ] && log_ok "Preserved deployment state file: ${STATE_FILE}"

echo ""
echo -e "${C_GREEN}${C_BOLD}CLEANUP COMPLETE${C_RESET}"
[ "$DEEP_CLEAN" -eq 1 ] && echo -e "${C_YELLOW}(deep clean: rollback safety image also removed)${C_RESET}"
exit 0
