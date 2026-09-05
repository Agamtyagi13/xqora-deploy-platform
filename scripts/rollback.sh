#!/usr/bin/env bash
# rollback.sh
# Automated rollback mechanism for the XQORA deployment platform.
#
# Triggered automatically by deploy.sh on failure, or run manually:
#   ./scripts/rollback.sh [--reason "some reason"]
#
# Steps:
#   1. Stop the failed version
#   2. Restore the previously working version/configuration (from backups/ + "last-good" image tag)
#   3. Restart the previous environment
#   4. Verify the application is working again (health check)
#   5. Generate rollback logs / report

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
log_init "rollback"

REASON="manual invocation"
if [ "${1:-}" = "--reason" ] && [ -n "${2:-}" ]; then
  REASON="$2"
fi

ROLLBACK_REPORT="${LOG_DIR}/rollback-report-${RUN_ID}.txt"
COMPOSE="$(docker_compose_cmd)"

log_step "1/5  Stopping the failed version"
if [ -n "$COMPOSE" ] && [ -f "$COMPOSE_FILE" ]; then
  cd "$PROJECT_ROOT" || true
  $COMPOSE stop >>"$CURRENT_LOG_FILE" 2>&1 || log_warn "Nothing running to stop, or stop failed (continuing)."
  log_ok "Stopped current container(s)"
else
  log_warn "docker compose unavailable; attempting direct 'docker stop'."
  docker stop "$APP_NAME" >>"$CURRENT_LOG_FILE" 2>&1 || true
fi

log_step "2/5  Restoring previously working version"
LAST_GOOD_FILE="${BACKUP_DIR}/last-good-version.txt"
RESTORED_VERSION=""
if docker image inspect "${APP_NAME}:last-good" >/dev/null 2>&1; then
  RESTORED_VERSION="last-good"
  log_ok "Found '${APP_NAME}:last-good' image tag to restore"
elif [ -f "$LAST_GOOD_FILE" ]; then
  CANDIDATE="$(cat "$LAST_GOOD_FILE")"
  if docker image inspect "${APP_NAME}:${CANDIDATE}" >/dev/null 2>&1; then
    RESTORED_VERSION="$CANDIDATE"
    log_ok "Found backed-up version to restore: ${CANDIDATE}"
  fi
fi

if [ -z "$RESTORED_VERSION" ]; then
  log_error "No previous working version found to roll back to."
  {
    echo "XQORA Rollback Report"
    echo "======================"
    echo "Date/Time (UTC): $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "Triggered by:    ${REASON}"
    echo "Result:          FAILED - no previous good version available"
  } | tee "$ROLLBACK_REPORT" >> "$CURRENT_LOG_FILE"
  exit 1
fi

log_step "3/5  Restarting the previous environment"
export APP_VERSION="$RESTORED_VERSION"
if [ -n "$COMPOSE" ]; then
  if ! $COMPOSE up -d --no-build >>"$CURRENT_LOG_FILE" 2>&1; then
    log_error "Failed to restart previous environment via docker compose."
    {
      echo "XQORA Rollback Report"
      echo "======================"
      echo "Date/Time (UTC): $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
      echo "Triggered by:    ${REASON}"
      echo "Restored version attempted: ${RESTORED_VERSION}"
      echo "Result:          FAILED - could not restart container"
    } | tee "$ROLLBACK_REPORT" >> "$CURRENT_LOG_FILE"
    exit 1
  fi
else
  docker run -d --rm --name "$APP_NAME" -p "${HOST_PORT:-3000}:3000" \
    --network xqora-net "${APP_NAME}:${RESTORED_VERSION}" >>"$CURRENT_LOG_FILE" 2>&1
fi
log_ok "Restarted container(s) using version: ${RESTORED_VERSION}"

log_step "4/5  Verifying the application is working again"
HEALTH_URL="http://localhost:${HOST_PORT:-3000}/health"
ROLLBACK_HEALTHY=0
for attempt in 1 2 3 4 5; do
  sleep 2
  if command_exists curl; then
    RESP="$(curl -fsS "$HEALTH_URL" 2>>"$CURRENT_LOG_FILE")"
  else
    RESP="$(wget -qO- "$HEALTH_URL" 2>>"$CURRENT_LOG_FILE")"
  fi
  if echo "${RESP:-}" | grep -q '"status":"UP"\|"status": "UP"'; then
    ROLLBACK_HEALTHY=1
    log_ok "Post-rollback health check passed (attempt ${attempt})"
    break
  fi
  log_warn "Post-rollback health check attempt ${attempt} not healthy yet, retrying..."
done

log_step "5/5  Generating rollback logs"
RESULT_TEXT="SUCCESS"
[ "$ROLLBACK_HEALTHY" -eq 1 ] || RESULT_TEXT="COMPLETED BUT HEALTH CHECK FAILED"

{
  echo "XQORA Rollback Report"
  echo "======================"
  echo "Date/Time (UTC):     $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "Triggered by:        ${REASON}"
  echo "Restored version:    ${RESTORED_VERSION}"
  echo "Post-rollback health:$( [ "$ROLLBACK_HEALTHY" -eq 1 ] && echo ' UP' || echo ' DOWN' )"
  echo "Result:              ${RESULT_TEXT}"
} | tee "$ROLLBACK_REPORT" >> "$CURRENT_LOG_FILE"

state_write "ROLLED_BACK" "$RESTORED_VERSION" "$REASON"

if [ "$ROLLBACK_HEALTHY" -eq 1 ]; then
  echo -e "${C_GREEN}${C_BOLD}ROLLBACK SUCCESSFUL${C_RESET} (restored version: ${RESTORED_VERSION})"
  exit 0
else
  echo -e "${C_RED}${C_BOLD}ROLLBACK COMPLETED, BUT APPLICATION IS NOT HEALTHY${C_RESET}"
  exit 1
fi
