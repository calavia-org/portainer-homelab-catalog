# PROJECT KNOWLEDGE BASE

**Generated:** 2026-07-16

## OVERVIEW

Custom Portainer App Templates catalog for homelab self-hosted Docker stacks, designed for GitOps-driven server-side updates. Each stack is a docker-compose.yml plus optional config files, exposed through a single Portainer v3 templates.json manifest that Portainer reads directly from this repository's raw GitHub URL.

## STRUCTURE

```
portainer/
└── templates/v3/
    └── templates.json          # Portainer v3 catalog manifest — all stack definitions
network/
└── unifi-controller/
    ├── docker-compose.yml      # UniFi Network Controller + MongoDB 7.0
    ├── backup.sh               # Pre-upgrade backup script (mongodump + config archive)
    └── init-mongo.sh           # MongoDB user initialization
media/
└── plex/
    └── docker-compose.yml      # Plex Media Server with qnet static MAC
tests/
├── lib.sh                    # Standard test library (helpers + network lifecycle)
├── run.sh                    # Unified test runner (single stack or all stacks)
├── test-unifi-controller.sh
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Add new stack | Create `category/stack-name/docker-compose.yml`, then add entry to `portainer/templates/v3/templates.json` |
| Update stack metadata (env vars, descriptions, logos) | Edit `portainer/templates/v3/templates.json` |
| UniFi backup/rollback script | `network/unifi-controller/backup.sh` |
| CI pipeline | `.github/workflows/stack-tests.yml` |

## CONVENTIONS

- **Stack names**: kebab-case directories under category (`unifi-controller`, `plex`)
- **Category dirs**: `system`, `network`, `media`, `monitoring` — add new category dir if no fit
- **Docker Compose**: all stacks use `${VAR:-default}` syntax for env defaults, never hardcode secrets
- **Templates JSON**: each stack entry has `id` (sequential), `type: 3` (Compose stack), `repository.stackfile` pointing to compose file path
- **qnet networking**: Plex and UniFi use `qnet-static-bond0-0094fd` with fixed MAC addresses to preserve container identity across restarts
- **Healthchecks**: services that expose HTTP endpoints define `healthcheck` blocks with wget-based probes

## ANTI-PATTERNS

- Do NOT commit `.env` files — all defaults belong in `templates.json` env array and compose `${VAR:-default}` syntax
- Do NOT bump `id` values when adding stacks — append sequentially, never reuse IDs
- Do NOT use `latest` tag in production-facing notes; images in compose files use `:latest` but notes should reference stable paths

## TESTS

Run individual smoke tests locally (requires Docker):

```bash
bash tests/run.sh network/unifi-controller
```

Or run all tests at once:

```bash
bash tests/run.sh
```

CI runs each test in isolated GitHub Actions jobs on every push/PR using the unified runner.

**Test standard:** Each stack has a `test-<stack-name>.sh` that sources `tests/lib.sh`. The library provides:
- `pass` / `fail` output helpers
- `stack_dir` — resolve stack path from test script
- `wait_for_container` — wait until container is running
- `wait_for_http` — wait until HTTP endpoint is reachable
- `wait_for_mongodb` — wait until MongoDB accepts auth connections
- `docker_network_ensure` / `docker_network_remove` — external network lifecycle
- `standard_cleanup` / `full_cleanup` — compose down + optional network/temp cleanup

## GITOPS WORKFLOW

1. Make changes to stack definitions or `templates.json` in this repository
2. Open a PR — CI smoke tests validate stack integrity
3. Merge to `main` — Portainer automatically picks up changes on next template refresh
4. Server-side stacks update without manual intervention

**Portainer Server:** https://portainer.calavia.org

**Catalog URL:**
```
https://raw.githubusercontent.com/calavia-org/portainer-homelab-catalog/main/portainer/templates/v3/templates.json
```

## SAFE UPGRADES (UniFi Controller)

The UniFi stack includes a `unifi-backup` one-shot service that runs before the controller on every deploy. It compares the current controller image tag against the last backed-up version and the history of all backups:

- **Upgrade** (new tag): creates a `mongodump` + config archive, then starts the controller.
- **Downgrade** (revert to a previously deployed tag): **automatically restores** the matching backup, then starts the controller.
- **No change**: skips instantly.

**Rollback procedure** (documented in the templates.json note field):
1. Stop the stack in Portainer.
2. Identify the pre-upgrade backup timestamp folder.
3. Restore MongoDB: `docker run --rm -v <backup-path>:/backups mongo:7.0 mongorestore --drop --host=unifi-db -u <user> -p <pass> --authenticationDatabase=admin /backups/<timestamp>/mongo`
4. Extract config archive: `tar xzf <backup-path>/<timestamp>/unifi-config.tar.gz -C <config-path>`
5. Revert the image tag in `docker-compose.yml`, commit, and push to git. Portainer will auto-deploy on next refresh.

**Requires**: Docker Compose ≥2.20.0 for `service_completed_successfully` dependency condition.

**GitOps note**: The controller image tag is hardcoded in `docker-compose.yml`. Upgrades and downgrades happen by editing that file in git — never via Portainer UI environment variables.

## NOTES

- Portainer reads `templates.json` directly from the raw GitHub URL; changes are live after merge to `main`
- MongoDB 7.0 is pinned for UniFi — do not downgrade, older UniFi versions may fail
- Plex hardware transcoding mounts `/dev/dri` — verify NAS has Intel Quick Sync before enabling
