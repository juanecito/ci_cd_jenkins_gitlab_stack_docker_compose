# CLAUDE.md

Context for this project, summarizing the work done so far.

## Project

A local CI/CD stack run with Docker Compose. All files are in the project root:

- `docker-compose.yml`: services, network and volumes
- `.env`: variables used by the compose file (holds secrets, do not commit or paste values into docs)
- `.env-example`: template of every `.env` variable, no values; `generate-env.sh`: creates/completes `.env` (random alphanumeric passwords, TZ, Docker socket GID; keeps existing values, backs up to `.env.bak.*`); `.gitignore`: ignores `.env` and `.env.*`
- `README.md`: user documentation (usage, ports, volumes, backups, troubleshooting)
- `runner/register.sh`: registers the GitLab Runner on startup
- `LICENSE`: MIT, copyright Juan Maria Gomez Lopez; source/config files carry a `Copyright` + `SPDX-License-Identifier: MIT` header (keep it on new files)
- `.claude/skills/docker-containers/SKILL.md`: skill for adding and managing containers in this stack

## Services

| Service        | Image                  | Host ports              | Notes                                              |
|----------------|------------------------|-------------------------|----------------------------------------------------|
| `gitlab`       | `gitlab/gitlab-ce`     | 8929 (HTTP), 8443, 2224 (SSH) | `external_url` is `http://localhost:8929`; tuned for low memory (2 Puma workers, Sidekiq 10, Prometheus off); has a healthcheck with a 5 min start period |
| `jenkins`      | `jenkins/jenkins`      | 8080, 50000             | Runs as root and mounts the host Docker socket; the compose file currently uses the `latest` tag (README table still says `lts-jdk17`) |
| `gitlab-runner` | `gitlab/gitlab-runner` | none                  | Docker executor using the host socket; registered automatically by the one-shot `gitlab-runner-register` service (`runner/register.sh`, mints a bootstrap root API token via `gitlab-rails runner` over the host socket, then creates an instance runner via API); depends on GitLab being healthy |
| `sonarqube`    | `sonarqube:community`  | 9000                    | Uses `sonarqube_db`; needs host `vm.max_map_count=524288` |
| `sonarqube_db` | `postgres:16`          | none                    | Healthcheck via `pg_isready`; SonarQube waits for it |
| `registry`     | `registry:latest`      | 5000                     | Plain HTTP, no auth; needs `insecure-registries` set on any Docker daemon that pushes/pulls (host, and job containers when `RUNNER_MOUNT_DOCKER_SOCK=true`) |

All services share the `ci_net` bridge network and reach each other by service name (for example `http://gitlab:8929`, `http://sonarqube:9000`).

## Volumes

`gitlab_config`, `gitlab_logs`, `gitlab_data`, `jenkins_home`, `gitlab_runner_config`, `registry_data`, and the SonarQube volumes `gitlab_sonarqube_data`, `gitlab_sonarqube_extensions`, `gitlab_sonarqube_logs`, `gitlab_sonarqube_db`.

The SonarQube volumes use a `gitlab_` prefix only to group them with the stack. They are separate from GitLab's own volumes on purpose: sharing volumes between different applications can corrupt data.

## Decisions and history

1. Created the compose file for GitLab and Jenkins with a shared network, named volumes and an `.env` file.
2. Wrote the README documenting usage, access, ports, volumes, Jenkins-GitLab integration, backups and troubleshooting.
3. Asked whether Jenkins can use JDK 21: yes, via the `lts-jdk21` tag (not verified against Docker Hub). The user later switched the compose file to `jenkins/jenkins:latest` themselves.
4. Added SonarQube with a Postgres database. "Associated with GitLab volumes" was interpreted as same network and `gitlab_`-prefixed volumes, not mounting GitLab's real volumes. Updated the README to match.
5. Added `gitlab-runner` (Docker executor). Gave `ci_net` a fixed `name: ci_net` so job containers can join it via `--docker-network-mode ci_net`. Registration is automatic via `runner/register.sh`; manual fallback is in the README. Auto-registration fails if the root password was changed after GitLab's first start.
6. First real `docker compose up` (2026-09-22) failed: `gitlab-runner-register` errored because GitLab 19.4.0 (`gitlab-ce:latest`) has removed the OAuth `password` grant type register.sh relied on to log in as root (`/oauth/token` now returns `400 unsupported_grant_type`, regardless of `.env`). Fixed by having `register.sh` mint a short-lived root API token via `gitlab-rails runner`, executed inside the `gitlab` container over the Docker Engine API (`/var/run/docker.sock`, now mounted into `gitlab-runner-register`); the token is revoked once the runner is registered. Verified end to end: `gitlab-runner-register` exits 0 and `gitlab-runner` registers and starts.
7. Added `registry` (the official Docker Registry image) so Jenkins/GitLab CI jobs have somewhere to push built images. Uses `registry:latest`, matching `gitlab`, `jenkins` and `gitlab-runner` (initially pinned to `2.8.3`, per the skill's default of preferring pinned tags, but switched to `latest` for consistency with the rest of the stack). No auth/TLS configured (matches this stack's local/dev scope); documented the `insecure-registries` daemon.json setting needed to push/pull from the host or from job containers.

## Conventions

- Named volumes, not bind mounts, for persistent data.
- Secrets go in `.env` and are referenced as `${VAR}` in the compose file.
- Every stateful service gets a named volume; every service joins `ci_net`.
- Add a healthcheck to services other services depend on, and use `depends_on` with `condition: service_healthy`.
- Keep the README in sync with the compose file (services table, ports, volumes, `.env` variables) whenever either changes.
- Validate changes with `docker compose config -q` before starting anything.

## Known caveats

- The `.env` GitLab root password contains a `$`. Compose interpolates `$` in `.env` values, so if login fails, write it as `$$` or wrap the value in single quotes. GitLab only reads the password on first initialization.
- The Jenkins image does not include the Docker CLI, so pipelines that call `docker` need a custom image or a Docker plugin.
- GitLab needs about 4 GB of RAM and SonarQube about 2 GB more.
- SonarQube Community edition does not decorate GitLab merge requests or analyze branches.
- The `registry` container serves plain HTTP with no authentication. Any Docker daemon that pushes/pulls to it (the host, or job containers when `RUNNER_MOUNT_DOCKER_SOCK=true`) needs `registry:5000`/`localhost:5000` added to `insecure-registries` in `/etc/docker/daemon.json`, or pushes fail with a TLS error.
- The full stack has been started and verified working (2026-09-22): GitLab, Jenkins, SonarQube+db, gitlab-runner and gitlab-runner-register all came up and the runner auto-registered successfully.
