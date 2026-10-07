---
name: docker-containers
description: Add, change or manage containers in this project's Docker Compose stack (GitLab, Jenkins, SonarQube). Use when asked to create a new service, adjust ports, volumes, env vars or healthchecks, or start, stop and inspect containers.
---

# Managing containers in this stack

Follow this workflow whenever a container is added or changed. The stack lives in `docker-compose.yml` in the project root, with variables in `.env` and documentation in `README.md`.

## 1. Before editing

- Read `docker-compose.yml`, `.env` and `CLAUDE.md` to see current services, ports and volumes.
- Check for conflicts: host ports already used by other services, and existing service or volume names.
- If the request is ambiguous (for example "associated with" another service's volumes), pick the safe reading and state it. Never mount one application's data volume into another.

## 2. Adding a service

Use this template and adjust it:

```yaml
  <name>:
    image: <image>:<pinned-tag>
    container_name: <name>
    restart: unless-stopped
    environment:
      SOME_VAR: "${SOME_VAR}"
    ports:
      - "<host>:<container>"
    volumes:
      - <stack>_<name>_data:/path/in/container
    networks:
      - ci_net
    depends_on:
      <dependency>:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "..."]
      interval: 30s
      timeout: 10s
      retries: 5
```

Rules:

1. Prefer a pinned image tag over `latest`, so upgrades are deliberate.
2. Put every secret in `.env` and reference it with `${VAR}`. Never hard-code passwords in the compose file, README or CLAUDE.md.
3. Use named volumes for persistent data, declared in the top-level `volumes:` section.
4. Attach the service to `ci_net` so it can reach the others by service name.
5. Add a healthcheck to anything other services depend on (databases, GitLab), and use `condition: service_healthy`.
6. Publish only the ports a user needs from the host. Databases and internal services get no `ports:` entry.
7. Note host requirements (kernel settings, `ulimits`, RAM) in the README.

## 3. Validate

```bash
docker compose config -q      # syntax and variable check; must print nothing
docker compose config         # optional: view the resolved file
```

If Docker is not available, say the file was not validated.

## 4. Run and inspect

Only start containers when the user asks or approves.

```bash
docker compose up -d <service>          # start or recreate one service
docker compose ps                       # status and health
docker compose logs -f <service>        # follow logs
docker compose restart <service>
docker compose pull <service>           # fetch a newer image
docker compose down                     # stop, keep data
```

`docker compose down -v` deletes all volumes and their data. Get explicit confirmation from the user before running it, and before removing any single volume.

## 5. Update the docs

After any change to services, ports, volumes or `.env` variables, update:

- `README.md`: services table, requirements, `.env` variable table, access table, ports table, volumes table, backups, troubleshooting.
- `CLAUDE.md`: services table, volumes list, decisions and history, known caveats.

## 6. Report

End with what changed, what was validated, and what was not run. Say plainly if containers were never started.

## Checklist

- [ ] No port, service or volume name conflicts
- [ ] Secrets are in `.env` and referenced with `${VAR}`
- [ ] Named volumes declared; service on `ci_net`
- [ ] Healthcheck and `depends_on` where needed
- [ ] `docker compose config -q` passes
- [ ] README.md and CLAUDE.md updated
