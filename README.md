# XQORA DevOps Environment Provisioning & One-Click Deployment Platform

A self-contained system that automatically provisions a local deployment
environment and deploys a demo application with a single command —
including validation, health-checking, automated rollback on failure, and
environment cleanup.

## 1. What's included

```
xqora-deploy-platform/
├── app/                        # Demo application (Node.js/Express)
│   ├── server.js                #   - REST API + health-check endpoint
│   ├── package.json
│   ├── public/index.html        #   - Basic frontend
│   └── Dockerfile
├── docker-compose.yml          # Container + network definition
├── config/
│   └── .env.example            # Config template (setup.sh generates the real .env)
├── scripts/
│   ├── common.sh                # Shared logging/helper library (sourced, not run directly)
│   ├── setup.sh                 # 1. Environment validation & setup
│   ├── deploy.sh                # 2. One-command deployment
│   ├── rollback.sh              # 3. Automated rollback
│   └── cleanup.sh               # 4. Environment cleanup
├── logs/                        # Timestamped run logs + deployment/rollback reports
├── backups/                     # Last-known-good version pointer
└── .deploy-state.json          # Current deployment state (created at runtime)
```

## 2. Demo application

A minimal Express app satisfying the three required pieces:

| Requirement          | Implementation                                   |
|-----------------------|---------------------------------------------------|
| Frontend/web interface | `app/public/index.html` — buttons that call the API |
| Backend/API            | `GET /api/info`, `GET /api/visits`, `GET /api/echo` |
| Health-check endpoint  | `GET /health` → `{"status":"UP", ...}`            |

## 3. Prerequisites

- Docker Engine (with the `docker compose` plugin, or standalone `docker-compose`)
- Bash (Linux/macOS/WSL)
- `curl` or `wget`

If any of these are missing, `setup.sh` will detect it and print a specific,
actionable message rather than failing silently.

## 4. Quick start (one command)

```bash
chmod +x scripts/*.sh
./scripts/deploy.sh
```

That single command will:

1. **Validate the environment** — checks Docker is installed and running,
   Docker Compose is available, the target port is free (auto-picks the next
   free port if not), required directories exist, and writes `.env`.
2. **Build the application** into a Docker image.
3. **Create the Docker image(s)** via `docker compose build`.
4. **Start the required container(s)** via `docker compose up -d`.
5. **Configure networking** — verifies the `xqora-net` bridge network and that
   the app's port is actually listening.
6. **Perform health checks** — polls `/health` (up to 10 attempts, 3s apart)
   and confirms the container is in a `running` state.
7. **Confirm deployment** — prints `DEPLOYMENT SUCCESSFUL` (or
   `DEPLOYMENT FAILED` with the reason) and writes a full report to
   `logs/deployment-report-<timestamp>.txt`.

No manual steps are required after running `./scripts/deploy.sh`. On success,
the app is reachable at `http://localhost:3000` (or the fallback port chosen
by `setup.sh` if 3000 was busy).

## 5. Automated rollback

If any deployment step fails, `deploy.sh` automatically invokes
`rollback.sh`, which will:

1. Stop the failed version's container(s).
2. Restore the last known-good image (tagged `xqora-demo-app:last-good`,
   tracked in `backups/last-good-version.txt`).
3. Restart the previous environment.
4. Re-run the health check to confirm the rollback actually works.
5. Write `logs/rollback-report-<timestamp>.txt`.

You can also trigger it manually:

```bash
./scripts/rollback.sh --reason "manual test"
```

## 6. Cleanup

```bash
./scripts/cleanup.sh          # normal cleanup
./scripts/cleanup.sh --all    # deep clean - also drops the rollback safety image
```

This stops and removes project containers, removes dangling/unused images,
deletes `*.tmp`/`*.pid` files, and trims old logs (keeping the most recent 10
of each type). It always preserves `.env`, the `backups/` directory, and
`.deploy-state.json`.

## 7. Logging & reports

Every script writes a timestamped log to `logs/<script>-<timestamp>.log`.
`deploy.sh` and `rollback.sh` additionally generate a human-readable report
containing:

- Deployment date/time
- Version/build
- Deployment status (`DEPLOYMENT SUCCESSFUL` / `DEPLOYMENT FAILED`)
- Health-check results
- Errors (if any)
- Rollback status

## 8. Configuration

`setup.sh` generates `.env` from these environment variables (all optional,
with sensible defaults):

| Variable      | Default | Purpose                          |
|---------------|---------|-----------------------------------|
| `APP_VERSION` | `1.0.0` | Image tag / reported build version |
| `HOST_PORT`   | `3000`  | Port the app is published on       |

Example: deploy a specific version on a specific port:

```bash
APP_VERSION=1.2.0 HOST_PORT=8080 ./scripts/deploy.sh
```

## 9. Testing failure & rollback locally

To see the failure/rollback path in action, temporarily break the health
endpoint (e.g. change `/health` to return a 500) and re-run `./scripts/deploy.sh` —
it will report `DEPLOYMENT FAILED`, automatically roll back to the last good
image, and confirm the rollback's own health check.

## 10. 6-Day build plan (for reference)

| Day | Task |
|-----|------|
| 1 | Design project architecture and create the demo application |
| 2 | Containerize the application using Docker and Docker Compose |
| 3 | Develop automated environment validation and setup scripts |
| 4 | Build the one-command deployment automation |
| 5 | Implement deployment validation, rollback, and logging |
| 6 | Create cleanup automation, perform testing, and prepare final documentation |
