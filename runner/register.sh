#!/bin/bash
# Copyright (c) 2026 Juan Maria Gomez Lopez <juan-maria.gomez-lopez@tutamail.com>
# SPDX-License-Identifier: MIT

# One-shot: creates an instance runner in GitLab through the API and registers it
# in the shared config volume. Safe to re-run: it does nothing if a runner is already registered.
set -euo pipefail

CONFIG=/etc/gitlab-runner/config.toml
GITLAB_URL="${GITLAB_URL:-http://gitlab:8929}"
GITLAB_CONTAINER="${GITLAB_CONTAINER_NAME:-gitlab}"
DOCKER_SOCK=/var/run/docker.sock

if [ -f "$CONFIG" ] && grep -q '^\[\[runners\]\]' "$CONFIG"; then
  echo "Runner already registered, nothing to do."
  exit 0
fi

echo "Waiting for GitLab at $GITLAB_URL ..."
until curl -fsS -o /dev/null "$GITLAB_URL/users/sign_in"; do sleep 10; done

# GitLab removed the OAuth "password" grant type (logging in as root with
# GITLAB_ROOT_PASSWORD through /oauth/token no longer works: it returns
# "unsupported_grant_type"). Mint a short-lived root API token instead by
# running gitlab-rails inside the gitlab container over the Docker socket.
echo "Creating a short-lived API token for root via gitlab-rails ..."
RUBY_SCRIPT='token = User.find_by_username!("root").personal_access_tokens.create!(scopes: [:api], name: "runner-bootstrap", expires_at: 1.day.from_now); puts %(RUNNER_BOOTSTRAP_TOKEN=#{token.token})'
EXEC_PAYLOAD=$(printf '{"Cmd":["gitlab-rails","runner","%s"],"AttachStdout":true,"AttachStderr":true,"Tty":true}' \
  "$(printf '%s' "$RUBY_SCRIPT" | sed 's/\\/\\\\/g; s/"/\\"/g')")

EXEC_ID=$(curl -fsS --unix-socket "$DOCKER_SOCK" -H "Content-Type: application/json" \
  -d "$EXEC_PAYLOAD" "http://localhost/containers/$GITLAB_CONTAINER/exec" \
  | sed -n 's/.*"Id":"\([^"]*\)".*/\1/p')
if [ -z "$EXEC_ID" ]; then
  echo "ERROR: could not open a docker exec session on the '$GITLAB_CONTAINER' container." >&2
  echo "Is /var/run/docker.sock mounted into this service? See README for manual registration." >&2
  exit 1
fi

ACCESS_TOKEN=$(curl -fsS --unix-socket "$DOCKER_SOCK" -H "Content-Type: application/json" \
  -d '{"Detach":false,"Tty":true}' "http://localhost/exec/$EXEC_ID/start" \
  | tr -d '\r' | sed -n 's/^RUNNER_BOOTSTRAP_TOKEN=//p' | tail -1)
if [ -z "${ACCESS_TOKEN:-}" ]; then
  echo "ERROR: could not mint a root API token via gitlab-rails. Register the runner manually (see README)." >&2
  exit 1
fi

echo "Creating the instance runner ..."
RUNNER_TOKEN=$(curl -fsS --request POST "$GITLAB_URL/api/v4/user/runners" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --data-urlencode "runner_type=instance_type" \
  --data-urlencode "description=${RUNNER_NAME:-docker-runner}" \
  --data-urlencode "tag_list=${RUNNER_TAGS:-docker}" \
  --data-urlencode "run_untagged=true" \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [ -z "$RUNNER_TOKEN" ]; then
  echo "ERROR: GitLab did not return a runner token." >&2
  exit 1
fi

# The bootstrap token has done its job; revoke it instead of leaving it valid
# for its full 1-day expiry.
curl -fsS --request DELETE --header "Authorization: Bearer $ACCESS_TOKEN" \
  "$GITLAB_URL/api/v4/personal_access_tokens/self" >/dev/null || true

echo "Registering the runner ..."
EXTRA_ARGS=()
if [ "${RUNNER_MOUNT_DOCKER_SOCK:-false}" = "true" ]; then
  EXTRA_ARGS+=(--docker-volumes /var/run/docker.sock:/var/run/docker.sock)
fi
gitlab-runner register --non-interactive \
  --url "$GITLAB_URL" \
  --clone-url "$GITLAB_URL" \
  --token "$RUNNER_TOKEN" \
  --name "${RUNNER_NAME:-docker-runner}" \
  --executor docker \
  --docker-image "${RUNNER_DEFAULT_IMAGE:-alpine:latest}" \
  --docker-network-mode "${RUNNER_NETWORK:-ci_net}" \
  --docker-pull-policy if-not-present \
  "${EXTRA_ARGS[@]}"

sed -i "s/^concurrent = .*/concurrent = ${RUNNER_CONCURRENT:-2}/" "$CONFIG"
echo "Runner registered."
