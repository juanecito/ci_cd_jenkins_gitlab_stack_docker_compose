# GitLab + Jenkins with Docker Compose

A local CI/CD environment running GitLab, Jenkins, a GitLab Runner and SonarQube (plus its database) on a shared network. It is meant for local development and learning, not for production or exposure to the internet.

| Service | Image                       | Purpose                  |
|---------|-----------------------------|--------------------------|
| gitlab  | `gitlab/gitlab-ce:latest`   | Git hosting, code review |
| jenkins | `jenkins/jenkins:latest`    | Build/pipeline server    |
| gitlab-runner | `gitlab/gitlab-runner:latest` | CI runner (Docker executor) for GitLab CI |
| sonarqube | `sonarqube:community`     | Code quality analysis    |
| sonarqube_db | `postgres:16`          | SonarQube database       |
| registry | `registry:latest`         | Docker image registry    |
| agent_jenkins_cpp_trixie | `local/jenkins-agent-cpp:trixie` (built here) | Jenkins C/C++ agent, Debian 13 |
| agent_jenkins_cpp_bullseye | `local/jenkins-agent-cpp:bullseye` (built here) | Jenkins C/C++ agent, Debian 11 |
| agent_jenkins_cpp_stretch | `local/jenkins-agent-cpp:stretch` (built here) | Jenkins C/C++ agent, Debian 9 |

```text
 browser / git client
        |
        v   8929 (HTTP)  2224 (SSH)  8080  9000
+----------------------------- ci_net (bridge) -----------------------------+
|  gitlab  <----- webhooks ------ jenkins          sonarqube --> sonarqube_db |
|     ^                              |                  ^                     |
|     +----- gitlab-runner ----------+-- docker.sock -> host Docker          |
+---------------------------------------------------------------------------+
```

Containers reach each other by service name (`http://gitlab:8929`, `http://jenkins:8080`, `http://sonarqube:9000`). The browser and your host use `localhost` with the published ports.

## Quick start

```bash
sudo sysctl -w vm.max_map_count=524288   # needed by SonarQube, see below
docker compose up -d
docker compose ps                        # wait until gitlab is "healthy" (3-5 min)
```

Then open GitLab at http://localhost:8929. The runner registers itself once GitLab is healthy (see [GitLab Runner](#gitlab-runner-docker-executor)).

## Requirements

- Docker Engine 20.10+ and the Docker Compose plugin (`docker compose`)
- At least 6 GB of free RAM (GitLab is the heavy one, SonarQube needs about 2 GB more) and about 10 GB of disk
- Ports `8929`, `8443`, `2224`, `8080`, `9000`, `50000` and `5000` free on the host

## Files

- `docker-compose.yml`: service definitions, network and volumes
- `.env`: variables used by the compose file (holds secrets, ignored by git; create it with `generate-env.sh`)
- `.env-example`: template listing every `.env` variable, without values
- `generate-env.sh`: creates or completes `.env` (random passwords, host time zone, Docker socket GID)
- `.gitignore`: keeps `.env` and its backups out of version control
- `runner/register.sh`: script that registers the GitLab Runner automatically
- `agent_jenkins_cpp_trixie/`, `agent_jenkins_cpp_bullseye/`, `agent_jenkins_cpp_stretch/`: Dockerfiles of the C/C++ Jenkins agents (Debian 13, 11 and 9)
- `agent_jenkins_common/`: files shared by all agent images (`entrypoint.sh`)
- `README.md`: this documentation
- `LICENSE`: MIT license

## Configuration

Create `.env` before the first start:

```bash
./generate-env.sh
```

It generates random 32-character alphanumeric passwords, detects the host time zone and the GID of `/var/run/docker.sock`, and writes `.env` with mode `600`. Re-running it is safe: existing values are kept, only missing ones are filled in, and the previous file is saved as `.env.bak.<timestamp>.<suffix>` whenever something changes. To fill `.env` by hand instead, copy `.env-example` to `.env`.

| Variable               | Set by `generate-env.sh`   | Description                                   |
|------------------------|----------------------------|-----------------------------------------------|
| `GITLAB_ROOT_PASSWORD` | Random password            | Initial password for GitLab's `root` user     |
| `SONAR_DB_PASSWORD`    | Random password            | Password for the SonarQube Postgres database  |
| `TZ`                   | Host time zone (or `UTC`)  | Time zone for Jenkins and GitLab Runner       |
| `DOCKER_GID`           | GID of `/var/run/docker.sock` | Group added to the Jenkins agents so they can use the host Docker |
| `CPP_TRIXIE_AGENT_SECRET`   | Left empty            | Secret of the `cpp-agent-trixie` node in Jenkins (see [Jenkins C/C++ agents](#jenkins-cc-agents)) |
| `CPP_BULLSEYE_AGENT_SECRET` | Left empty            | Secret of the `cpp-agent-bullseye` node in Jenkins |
| `CPP_STRETCH_AGENT_SECRET`  | Left empty            | Secret of the `cpp-agent-stretch` node in Jenkins |

Options: `--agent-secret <release>=<secret>` (repeatable; `<release>` is `trixie`, `bullseye` or `stretch`) stores a Jenkins agent secret, `--new-passwords` regenerates both passwords, `-o <file>` writes somewhere else, `--help` shows all of them.

> GitLab and Postgres only read their passwords on first initialization. To change them later, use GitLab's UI or `gitlab-rake`, and `ALTER USER` in Postgres. `--new-passwords` on an existing stack only changes `.env`, which breaks SonarQube's database login.
> Avoid `$` and `'` in hand-written values: Compose interpolates `$`, and `'` breaks GitLab's configuration.
> Never commit `.env`; `.gitignore` already excludes it.

## Usage

```bash
# Start all services in the background
docker compose up -d

# Follow logs
docker compose logs -f gitlab
docker compose logs -f jenkins
docker compose logs -f gitlab-runner

# Restart or stop a single service
docker compose restart jenkins
docker compose stop sonarqube

# Open a shell inside a container
docker compose exec gitlab bash

# Check status (GitLab shows "healthy" when ready)
docker compose ps

# Stop (data is kept)
docker compose down

# Stop and delete all data
docker compose down -v
```

## Access

| Service | URL                     | Credentials                                         |
|---------|-------------------------|-----------------------------------------------------|
| GitLab  | http://localhost:8929   | user `root`, password from `.env`                   |
| Jenkins | http://localhost:8080   | initial admin password (see below)                  |
| SonarQube | http://localhost:9000 | `admin` / `admin` (you must change it on first login) |
| Registry  | http://localhost:5000 | none (no authentication configured)                  |

GitLab takes 3-5 minutes to become ready on first start. Until then it returns 502 errors.

Get the Jenkins unlock key:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Then follow the setup wizard and install the suggested plugins.

## Ports

| Host port | Container | Use                              |
|-----------|-----------|----------------------------------|
| 8929      | gitlab    | GitLab web UI (HTTP)             |
| 8443      | gitlab    | GitLab HTTPS (maps to 443)       |
| 2224      | gitlab    | Git over SSH (maps to 22)        |
| 8080      | jenkins   | Jenkins web UI                   |
| 50000     | jenkins   | Jenkins inbound agents           |
| 9000      | sonarqube | SonarQube web UI                 |
| 5000      | registry  | Docker Registry API              |

Clone over SSH with a non-standard port:

```bash
git clone ssh://git@localhost:2224/<group>/<project>.git
```

## Volumes

| Volume          | Mounted at              | Holds                         |
|-----------------|-------------------------|-------------------------------|
| `gitlab_config` | `/etc/gitlab`           | GitLab configuration, secrets |
| `gitlab_logs`   | `/var/log/gitlab`       | GitLab logs                   |
| `gitlab_data`   | `/var/opt/gitlab`       | Repositories, database        |
| `jenkins_home`  | `/var/jenkins_home`     | Jobs, plugins, credentials    |
| `gitlab_runner_config` | `/etc/gitlab-runner` | GitLab Runner config (`config.toml`) |
| `gitlab_sonarqube_data` | `/opt/sonarqube/data` | SonarQube search index, analysis data |
| `gitlab_sonarqube_extensions` | `/opt/sonarqube/extensions` | SonarQube plugins |
| `gitlab_sonarqube_logs` | `/opt/sonarqube/logs` | SonarQube logs |
| `gitlab_sonarqube_db` | `/var/lib/postgresql/data` | SonarQube Postgres data |
| `registry_data` | `/var/lib/registry`      | Pushed Docker images          |
| `cpp_agent_<release>_work` | `/home/jenkins/agent` | Jenkins agent workspace (one per agent: `trixie`, `bullseye`, `stretch`) |
| `cpp_agent_<release>_ccache` | `/home/jenkins/.ccache` | ccache compiler cache (one per agent) |

The SonarQube volumes use a `gitlab_` prefix to group them with the GitLab stack, but they are separate from GitLab's own volumes. Do not mount GitLab's volumes into SonarQube, because sharing them can corrupt data.

## GitLab Runner (Docker executor)

The runner is installed and registered automatically on `docker compose up -d`:

1. `gitlab-runner-register` (a one-shot container) waits for GitLab to be healthy.
2. It mints a short-lived root API token by running `gitlab-rails runner` inside the `gitlab` container over the mounted `/var/run/docker.sock` (GitLab removed OAuth password-grant login, so `GITLAB_ROOT_PASSWORD` can no longer be used to fetch a token via the API), creates an **instance runner** through the API (tag `docker`, also runs untagged jobs), revokes the token and registers the runner with the Docker executor.
3. The result is stored in the `gitlab_runner_config` volume, and `gitlab-runner` starts once registration succeeds.

Jobs run in containers started on the host through the mounted `/var/run/docker.sock`. They join `ci_net` and clone from `http://gitlab:8929`, so they can reach GitLab and SonarQube by service name. If a runner is already registered, the register container exits without changes, so restarts and `up -d` are safe.

Optional variables in `.env` (all have defaults):

| Variable                   | Default          | Description                                                        |
|----------------------------|------------------|--------------------------------------------------------------------|
| `RUNNER_NAME`              | `docker-runner`  | Runner description shown in GitLab                                 |
| `RUNNER_TAGS`              | `docker`         | Comma-separated runner tags                                        |
| `RUNNER_DEFAULT_IMAGE`     | `alpine:latest`  | Image used when a job has no `image:`                              |
| `RUNNER_CONCURRENT`        | `2`              | Jobs the runner executes in parallel                               |
| `RUNNER_MOUNT_DOCKER_SOCK` | `false`          | `true` mounts the host Docker socket into every job (for `docker build`) |

Check the result with `docker compose logs gitlab-runner-register` and Admin Area -> CI/CD -> Runners.

**Re-registering:** the register step only runs when `config.toml` has no runner. To start over, remove the runner in GitLab, then `docker compose down`, `docker volume rm gitlab_runner_config` and `docker compose up -d`.

**If automatic registration fails** (for example if `/var/run/docker.sock` isn't reachable from `gitlab-runner-register`, or GitLab's root account is locked/2FA-protected), create a runner in the UI (Admin Area -> CI/CD -> Runners -> New instance runner), copy the `glrt-` token and register it by hand:

```bash
docker compose exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url http://gitlab:8929 \
  --clone-url http://gitlab:8929 \
  --token <glrt-token> \
  --executor docker \
  --docker-image alpine:latest \
  --docker-network-mode ci_net
```

Then start the runner with `docker compose up -d --no-deps gitlab-runner`. Without `--clone-url` and `--docker-network-mode ci_net`, jobs fail to clone because `localhost` inside a job container is not GitLab.

### Example `.gitlab-ci.yml`

A minimal pipeline that runs on the registered runner and, optionally, sends the code to SonarQube. Add it to the root of a GitLab project:

```yaml
stages: [build, scan]

build:
  stage: build
  image: alpine:latest
  script:
    - echo "Building on $(hostname)"

sonarqube:
  stage: scan
  image:
    name: sonarsource/sonar-scanner-cli:latest
    entrypoint: [""]
  variables:
    SONAR_HOST_URL: http://sonarqube:9000
  script:
    - sonar-scanner -Dsonar.projectKey=$CI_PROJECT_NAME -Dsonar.token=$SONAR_TOKEN
  allow_failure: true
```

Store the SonarQube token as a masked CI/CD variable named `SONAR_TOKEN` (project Settings -> CI/CD -> Variables). `http://sonarqube:9000` works because job containers join `ci_net`.

### Runner management

```bash
docker compose exec gitlab-runner gitlab-runner list      # registered runners
docker compose exec gitlab-runner gitlab-runner verify    # check they can reach GitLab
docker compose exec gitlab-runner gitlab-runner unregister --all-runners
```

To change concurrency or add volumes later, set the `RUNNER_*` variables before the first start or edit `config.toml` inside the volume (`docker compose exec gitlab-runner vi /etc/gitlab-runner/config.toml`); the runner reloads it automatically.

## Start automatically on boot

All services use `restart: unless-stopped`, so Docker restarts them whenever the Docker daemon starts. You only need to enable the daemon at boot:

```bash
sudo systemctl enable docker
sudo systemctl is-enabled docker   # should print "enabled"
```

Behavior after a reboot:

- All containers come back without running `docker compose up`.
- `depends_on` ordering is not applied on restart. `sonarqube` may start before `sonarqube_db` is ready, fail to connect, and restart until the database is up. This settles within a minute or two.
- A container you stopped by hand (`docker compose stop` or `docker stop`) stays stopped after a reboot.
- `docker compose down` removes the containers, so nothing restarts after it.

### Optional: systemd unit

A systemd unit gives ordered startup with `docker compose up -d` and lets you use `systemctl start/stop`. Create `/etc/systemd/system/ci-stack.service`:

```ini
[Unit]
Description=GitLab, Jenkins and SonarQube stack
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/juanitov/docker_gitlab_jenkins
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose stop
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

Then enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable ci-stack.service
```

`ExecStop` uses `stop`, not `down`, so containers are kept and only stopped. Adjust `WorkingDirectory` if the project is in another path.

## Connecting Jenkins to GitLab

Both containers are on the `ci_net` network, so Jenkins reaches GitLab by service name:

- Use `http://gitlab:8929` in Jenkins job or credential settings (container-to-container).
- Use `http://localhost:8929` in your browser.

Steps:

1. In Jenkins, install the **GitLab** and **Git** plugins (Manage Jenkins -> Plugins).
2. In GitLab, create a Personal Access Token (User Settings -> Access Tokens) with the `api` and `read_repository` scopes.
3. In Jenkins, add it under Manage Jenkins -> Credentials, as "GitLab API token" and/or a "Username with password" entry.
4. Configure the GitLab connection in Manage Jenkins -> System, with host URL `http://gitlab:8929`.
5. Create a pipeline job pointing at `http://gitlab:8929/<group>/<project>.git`.
6. To trigger builds on push, add a webhook in the GitLab project (Settings -> Webhooks) pointing to `http://jenkins:8080/project/<job-name>`.

GitLab blocks webhooks to local addresses by default. Enable **Allow requests to the local network from webhooks** under Admin Area -> Settings -> Network -> Outbound requests.

## SonarQube

SonarQube runs on the same `ci_net` network, so other containers reach it at `http://sonarqube:9000`.

**Host requirement:** SonarQube's embedded Elasticsearch fails to start unless the host allows enough memory maps. Run this before `docker compose up`:

```bash
sudo sysctl -w vm.max_map_count=524288
# make it permanent
echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
```

First login: `admin` / `admin`, then set a new password. SonarQube takes 1-2 minutes to start.

### Using it with GitLab and Jenkins

1. In SonarQube, create a token (My Account -> Security -> Generate Tokens).
2. In Jenkins, install the **SonarQube Scanner** plugin.
3. Add the token as a "Secret text" credential (Manage Jenkins -> Credentials).
4. Add the server in Manage Jenkins -> System -> SonarQube servers, with URL `http://sonarqube:9000`.
5. In your pipeline, wrap the scan:

```groovy
withSonarQubeEnv('<server-name>') {
  sh 'sonar-scanner -Dsonar.projectKey=<project>'
}
```

The Community edition analyzes projects but does not decorate GitLab merge requests or analyze branches. Those features need Developer edition or higher.

## Docker Registry

A private Docker Registry (the official `registry` image) runs on `ci_net` and is reachable from other containers at `http://registry:5000`, and from the host at `http://localhost:5000`.

It has no authentication or TLS configured, so both the Docker daemon on the host and, if `RUNNER_MOUNT_DOCKER_SOCK=true`, job containers using the host's Docker socket must be told to treat it as insecure before they can push or pull:

```json
{
  "insecure-registries": ["localhost:5000", "registry:5000"]
}
```

Add this to `/etc/docker/daemon.json` on the host and restart Docker (`sudo systemctl restart docker`).

```bash
# push an image built on the host
docker tag myimage:latest localhost:5000/myimage:latest
docker push localhost:5000/myimage:latest

# from a job container on ci_net
docker tag myimage:latest registry:5000/myimage:latest
docker push registry:5000/myimage:latest

# list what's stored
curl http://localhost:5000/v2/_catalog
```

## Notes

- **Docker socket:** Jenkins mounts `/var/run/docker.sock` so pipelines can run Docker commands. This gives Jenkins root-equivalent control of the host's Docker. Remove that volume line if you do not need it. The Jenkins image also does not include the Docker CLI; install it in a custom image or use a Docker agent/plugin.
- **Runner and the Docker socket:** `gitlab-runner` also mounts the host Docker socket, with the same root-equivalent risk as Jenkins. Only run trusted pipelines.
- **Register step and the Docker socket:** `gitlab-runner-register` also mounts the host Docker socket, so it can run `gitlab-rails runner` inside the `gitlab` container to mint its own bootstrap API token. It's a one-shot container and revokes that token once the runner is registered, but the socket access itself is still root-equivalent for the duration.
- **Jenkins agents and the Docker socket:** the three C/C++ agents mount the host Docker socket and join its group (`DOCKER_GID`), so any pipeline that runs on them has root-equivalent control of the host's Docker, even though the agents run as the unprivileged `jenkins` user.
- **Root user:** Jenkins runs as `root` so it can use the socket. For stricter setups, run as the default `jenkins` user and add the docker group instead.
- **Memory tuning:** GitLab is limited to 2 Puma workers, 10 Sidekiq threads and has Prometheus disabled. Raise these on larger hosts by editing `GITLAB_OMNIBUS_CONFIG`.
- **Changing the URL:** if you serve GitLab on another host or port, update `external_url` and the port mappings together, then run `docker compose up -d`.
- **Pin versions:** `latest` for GitLab can trigger upgrades you didn't plan for. Pin a specific tag (for example `gitlab/gitlab-ce:17.5.0-ce.0`) for stable setups.

## Backups

```bash
# GitLab application backup (stored in gitlab_data volume, /var/opt/gitlab/backups)
docker exec gitlab gitlab-backup create

# GitLab config and secrets are NOT included in the above; back up /etc/gitlab as well
docker run --rm -v gitlab_config:/data -v "$PWD":/backup alpine \
  tar czf /backup/gitlab_config.tgz -C /data .

# SonarQube database (or use pg_dump for a consistent dump)
docker exec sonarqube_db pg_dump -U sonar sonarqube > sonarqube.sql

# Jenkins home
docker run --rm -v jenkins_home:/data -v "$PWD":/backup alpine \
  tar czf /backup/jenkins_home.tgz -C /data .

# GitLab Runner config (contains the runner token)
docker run --rm -v gitlab_runner_config:/data -v "$PWD":/backup alpine \
  tar czf /backup/gitlab_runner_config.tgz -C /data .
```

### Restoring

```bash
# Restore a volume archive (stop the stack first; example for Jenkins)
docker compose down
docker run --rm -v jenkins_home:/data -v "$PWD":/backup alpine \
  sh -c "cd /data && tar xzf /backup/jenkins_home.tgz"

# Restore the SonarQube database (stack running)
docker exec -i sonarqube_db psql -U sonar sonarqube < sonarqube.sql

# Restore a GitLab backup: copy the archive into /var/opt/gitlab/backups, then
docker exec -it gitlab gitlab-backup restore BACKUP=<timestamp_and_version>
```

Restore the GitLab config archive too, or the backup's encrypted data cannot be read. Stop `puma` and `sidekiq` first with `docker exec gitlab gitlab-ctl stop puma` and `docker exec gitlab gitlab-ctl stop sidekiq`, and run `docker exec gitlab gitlab-ctl reconfigure` after restoring.

## Upgrading

```bash
docker compose pull
docker compose up -d
```

Back up first. GitLab can only upgrade along supported version paths, so do not skip major versions; pin a tag and move one step at a time. SonarQube Community also upgrades in steps, and the database must be backed up before a major upgrade.

## Jenkins C/C++ agents

Three inbound agents build C/C++ code on different Debian releases. They share the same toolchain (gcc, clang, cmake, ninja, Qt 5, libcurl, libpq, libapt-pkg, ccache, valgrind, cppcheck) at each release's own versions, plus the Docker CLI with Buildx and Compose.

| Service                       | Jenkins node          | Base image        | Java       | Notes |
|-------------------------------|-----------------------|-------------------|------------|-------|
| `agent_jenkins_cpp_trixie`    | `cpp-agent-trixie`    | `debian:trixie`   | Debian `openjdk-21` | Docker CLI from Docker's apt repository |
| `agent_jenkins_cpp_bullseye`  | `cpp-agent-bullseye`  | `debian:bullseye` | Temurin 21 (copied from `eclipse-temurin:21-jre`) | End of life: apt uses archive.debian.org |
| `agent_jenkins_cpp_stretch`   | `cpp-agent-stretch`   | `debian:stretch`  | Temurin 21 (copied from `eclipse-temurin:21-jre`) | End of life: apt uses archive.debian.org; no `lld` package; curlpp 0.8.1 built from source (not packaged for stretch) |

Jenkins' `agent.jar` needs Java 17 or newer, which stretch (Java 8) does not have, so the two older images copy the Java runtime and the static Docker CLI (`docker:29-cli`) from upstream images instead of installing them with apt. Bullseye and stretch get no more security updates; use them only to build for those releases.

All agents connect to `http://jenkins:8080` over WebSocket (port 50000 is not needed), run with `init: true` so tini reaps build processes, and copy `agent_jenkins_common/entrypoint.sh` through the `common` additional build context.

For each agent, create a node in Jenkins (Nodes -> New Node -> Permanent Agent):
- Name: `cpp-agent-trixie`, `cpp-agent-bullseye` or `cpp-agent-stretch`
- Remote root: `/home/jenkins/agent`
- Labels: `cpp docker <release>` (for example `cpp docker stretch`), so pipelines can pick a release with `agent { label 'cpp && stretch' }`
- Launch: Launch agent by connecting it to the controller

Save the node, copy the secret shown on its page and store it in `.env`:

```bash
./generate-env.sh --agent-secret trixie=<secret> --agent-secret bullseye=<secret> --agent-secret stretch=<secret>
```

Build and start the agents:

```bash
docker compose up -d --build agent_jenkins_cpp_trixie agent_jenkins_cpp_bullseye agent_jenkins_cpp_stretch
docker compose logs -f agent_jenkins_cpp_stretch   # must end with "Connected"
```

An agent without a secret in `.env` exits with `Missing JENKINS_SECRET` and keeps restarting; start only the agents you have created nodes for.

**Upgrading from the single `agent_jenkins_cpp` agent:** the service is now `agent_jenkins_cpp_trixie`, its node is `cpp-agent-trixie` and its secret is `CPP_TRIXIE_AGENT_SECRET`. Jenkins derives the secret from the node name, so rename the `cpp-agent` node in Jenkins (Configure -> Name), copy its new secret and run `./generate-env.sh --agent-secret trixie=<secret>`, which also drops the old `CPP_AGENT_SECRET`. Then remove the old container with `docker compose up -d --remove-orphans`. The old `cpp_agent_work` and `cpp_agent_ccache` volumes only hold a workspace and a compiler cache; delete them with `docker volume rm docker_gitlab_jenkins_cpp_agent_work docker_gitlab_jenkins_cpp_agent_ccache` once the new agent works.

## Troubleshooting

| Symptom                        | Fix                                                                                      |
|--------------------------------|------------------------------------------------------------------------------------------|
| GitLab shows 502               | Still starting; wait a few minutes and check `docker compose logs -f gitlab`             |
| GitLab container restarts / OOM | Give Docker more memory (4 GB minimum)                                                  |
| Cannot log in as `root`        | The password is only applied on first start; reset with `docker exec -it gitlab gitlab-rake "gitlab:password:reset[root]"` |
| Port already in use            | Change the left side of the port mapping in `docker-compose.yml`                         |
| SonarQube exits at startup     | Set `vm.max_map_count=524288` on the host (see the SonarQube section)                   |
| Jenkins cannot reach GitLab    | Use `http://gitlab:8929`, not `localhost`, inside Jenkins                                |
| Runner job fails to clone      | Register with `--clone-url http://gitlab:8929` and `--docker-network-mode ci_net`        |
| Job is stuck "pending"         | No runner online or no matching tags; check `gitlab-runner verify` and the Runners page  |
| Runner cannot register         | Read `docker compose logs gitlab-runner-register`; if it can't reach the Docker socket or mint a root token, register manually (see the runner section) |
| `docker: not found` in a job   | Use an image that includes the Docker CLI, such as `docker:cli`                          |
| `push`/`pull` to `registry` fails with a TLS error | Add `registry:5000` (and `localhost:5000`) to `insecure-registries` in `/etc/docker/daemon.json` and restart Docker |
| Agent keeps restarting with `Missing JENKINS_SECRET` | Create its node in Jenkins and run `./generate-env.sh --agent-secret <release>=<secret>` |
| bullseye/stretch agent build fails with `404 Not Found` from apt | The release moved to archive.debian.org; check the `sources.list` lines in its Dockerfile still match the archive layout |
| Disk fills up                  | Clean old images and job containers with `docker system prune` (add `--volumes` with care) |

## License

Copyright (c) 2026 Juan Maria Gomez Lopez <juan-maria.gomez-lopez@tutamail.com>

Released under the MIT License. See [LICENSE](LICENSE).
