#!/bin/bash
# Copyright (c) 2026 Juan Maria Gomez Lopez <juan-maria.gomez-lopez@tutamail.com>
# SPDX-License-Identifier: MIT

# Generates the .env file used by docker-compose.yml: random passwords, the host
# time zone, the GID of the host Docker socket and the Jenkins agent secrets. If .env already exists, its
# values are kept and only missing ones are filled in, so it is safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
NEW_PASSWORDS=false
# Debian releases of the C/C++ Jenkins agents; each has a CPP_<RELEASE>_AGENT_SECRET
AGENT_RELEASES=(trixie bullseye stretch)
declare -A AGENT_SECRETS=()

agent_var() { printf 'CPP_%s_AGENT_SECRET' "${1^^}"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Creates or completes $ENV_FILE.

Options:
  --agent-secret RELEASE=SECRET
                             Jenkins secret for the cpp-agent-RELEASE node (shown on
                             the node's page in Jenkins after creating it). RELEASE
                             is one of: ${AGENT_RELEASES[*]}. Can be repeated.
  --new-passwords            Regenerate GITLAB_ROOT_PASSWORD and SONAR_DB_PASSWORD
                             even if they are already set (see the warning below)
  -o, --output FILE          Write to FILE instead of .env
  -h, --help                 Show this help

GitLab and Postgres only read their passwords on first initialization. If the
volumes already exist, --new-passwords does not change the real passwords and
SonarQube will no longer be able to log in to its database.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --agent-secret)
      arg="${2:?--agent-secret needs RELEASE=SECRET}"
      release=${arg%%=*}
      secret=${arg#*=}
      if [[ "$arg" != *=* || " ${AGENT_RELEASES[*]} " != *" $release "* ]]; then
        echo "ERROR: --agent-secret expects RELEASE=SECRET with RELEASE one of: ${AGENT_RELEASES[*]}" >&2
        exit 1
      fi
      if ! [[ "$secret" =~ ^[A-Za-z0-9]+$ ]]; then
        echo "ERROR: the $release agent secret must be alphanumeric (Jenkins agent secrets are hex strings)." >&2
        exit 1
      fi
      AGENT_SECRETS[$release]=$secret
      shift 2 ;;
    --new-passwords)    NEW_PASSWORDS=true; shift ;;
    -o|--output)        ENV_FILE="${2:?--output needs a value}"; shift 2 ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Alphanumeric only: '$' is interpolated by Compose and "'" would break the
# Ruby string GitLab builds from GITLAB_OMNIBUS_CONFIG.
random_password() {
  local s
  s=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')
  printf '%s' "${s:0:32}"
}

detect_tz() {
  local tz=""
  if command -v timedatectl >/dev/null 2>&1; then
    tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  fi
  if [ -z "$tz" ] && [ -L /etc/localtime ]; then
    tz=$(readlink -f /etc/localtime | sed -n 's|.*/zoneinfo/||p')
  fi
  if [ -z "$tz" ] && [ -r /etc/timezone ]; then
    tz=$(head -1 /etc/timezone)
  fi
  printf '%s' "${tz:-UTC}"
}

detect_docker_gid() {
  if [ -S /var/run/docker.sock ]; then
    stat -c %g /var/run/docker.sock
  elif getent group docker >/dev/null 2>&1; then
    getent group docker | cut -d: -f3
  fi
}

# Read the existing .env literally (no `source`: values may contain '$').
declare -A OLD=()
OLD_KEYS=()
if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    OLD["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    OLD_KEYS+=("${BASH_REMATCH[1]}")
  done < "$ENV_FILE"
fi

NOTES=()

# Unset optional variables are written commented out with their Compose default.
optional() {
  local key=$1 default=$2
  if [ -n "${OLD[$key]:-}" ]; then
    echo "$key=${OLD[$key]}"
  else
    echo "# $key=$default"
  fi
}

if $NEW_PASSWORDS; then
  unset 'OLD[GITLAB_ROOT_PASSWORD]' 'OLD[SONAR_DB_PASSWORD]'
fi
for release in "${!AGENT_SECRETS[@]}"; do
  OLD[$(agent_var "$release")]="${AGENT_SECRETS[$release]}"
  NOTES+=("$(agent_var "$release"): set from --agent-secret")
done
# CPP_AGENT_SECRET belonged to the single "cpp-agent" node, now cpp-agent-trixie.
# Jenkins derives the secret from the node name, so it cannot be carried over.
OBSOLETE_KEYS=" CPP_AGENT_SECRET "
if [ -n "${OLD[CPP_AGENT_SECRET]+x}" ]; then
  NOTES+=("CPP_AGENT_SECRET: removed (obsolete; the trixie node now uses $(agent_var trixie))")
fi

# Keep existing values; generate or detect only the missing ones.
GITLAB_ROOT_PASSWORD=${OLD[GITLAB_ROOT_PASSWORD]:-}
[ -n "$GITLAB_ROOT_PASSWORD" ] || { GITLAB_ROOT_PASSWORD=$(random_password); NOTES+=("GITLAB_ROOT_PASSWORD: generated"); }
SONAR_DB_PASSWORD=${OLD[SONAR_DB_PASSWORD]:-}
[ -n "$SONAR_DB_PASSWORD" ] || { SONAR_DB_PASSWORD=$(random_password); NOTES+=("SONAR_DB_PASSWORD: generated"); }
TZ_VALUE=${OLD[TZ]:-}
[ -n "$TZ_VALUE" ] || { TZ_VALUE=$(detect_tz); NOTES+=("TZ: detected ($TZ_VALUE)"); }
DOCKER_GID_VALUE=${OLD[DOCKER_GID]:-}
if [ -z "$DOCKER_GID_VALUE" ]; then
  DOCKER_GID_VALUE=$(detect_docker_gid || true)
  if [ -n "$DOCKER_GID_VALUE" ]; then NOTES+=("DOCKER_GID: detected ($DOCKER_GID_VALUE)"); fi
fi
MISSING_SECRETS=()
for release in "${AGENT_RELEASES[@]}"; do
  [ -n "${OLD[$(agent_var "$release")]:-}" ] || MISSING_SECRETS+=("$release")
done

KNOWN_KEYS=" GITLAB_ROOT_PASSWORD SONAR_DB_PASSWORD TZ DOCKER_GID \
$(for r in "${AGENT_RELEASES[@]}"; do printf '%s ' "$(agent_var "$r")"; done)\
RUNNER_NAME RUNNER_TAGS RUNNER_DEFAULT_IMAGE RUNNER_CONCURRENT RUNNER_MOUNT_DOCKER_SOCK "

umask 077
TMP=$(mktemp "$ENV_FILE.XXXXXX")
trap 'rm -f "$TMP"' EXIT

{
  echo "# Generated by generate-env.sh. Holds secrets: never commit this file."
  echo
  echo "# Initial password for GitLab's root user (only read on GitLab's first start)"
  echo "GITLAB_ROOT_PASSWORD=$GITLAB_ROOT_PASSWORD"
  echo "# Password for the SonarQube Postgres database (only read on the database's first start)"
  echo "SONAR_DB_PASSWORD=$SONAR_DB_PASSWORD"
  echo
  echo "# Time zone for Jenkins and GitLab Runner"
  echo "TZ=$TZ_VALUE"
  echo "# GID that owns /var/run/docker.sock on the host (lets the Jenkins agents use Docker)"
  echo "DOCKER_GID=$DOCKER_GID_VALUE"
  echo "# Secrets of the C/C++ agent nodes, copied from Jenkins (Nodes -> cpp-agent-<release>)"
  for release in "${AGENT_RELEASES[@]}"; do
    key=$(agent_var "$release")
    echo "$key=${OLD[$key]:-}"
  done
  echo
  echo "# Optional GitLab Runner settings (defaults shown)"
  optional RUNNER_NAME docker-runner
  optional RUNNER_TAGS docker
  optional RUNNER_DEFAULT_IMAGE alpine:latest
  optional RUNNER_CONCURRENT 2
  optional RUNNER_MOUNT_DOCKER_SOCK false

  header_done=false
  for key in "${OLD_KEYS[@]}"; do
    [[ "$KNOWN_KEYS$OBSOLETE_KEYS" == *" $key "* ]] && continue
    if ! $header_done; then
      echo
      echo "# Other variables kept from the previous .env"
      header_done=true
    fi
    echo "$key=${OLD[$key]}"
  done
} > "$TMP"

if [ -f "$ENV_FILE" ]; then
  if cmp -s "$TMP" "$ENV_FILE"; then
    echo "$ENV_FILE is already complete, nothing to do."
    exit 0
  fi
  BACKUP=$(mktemp "$ENV_FILE.bak.$(date +%Y%m%d%H%M%S).XXXX")
  cp -p "$ENV_FILE" "$BACKUP"
  echo "Previous file saved as $BACKUP"
fi
mv "$TMP" "$ENV_FILE"
chmod 600 "$ENV_FILE"
trap - EXIT

echo "Wrote $ENV_FILE"
for note in "${NOTES[@]}"; do echo "  - $note"; done

if [ -z "$DOCKER_GID_VALUE" ]; then
  echo "WARNING: could not detect the Docker socket GID; set DOCKER_GID by hand." >&2
fi
if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
  echo "NOTE: no Jenkins secret yet for: ${MISSING_SECRETS[*]}. Create the cpp-agent-<release>" >&2
  echo "  node(s) in Jenkins, then run for each one:" >&2
  echo "  $0 --agent-secret <release>=<secret>" >&2
fi
if $NEW_PASSWORDS; then
  echo "WARNING: if the GitLab or SonarQube volumes already exist, the new passwords will not" >&2
  echo "  take effect there (see --help). Restore the backup if that is not what you want." >&2
fi
