#!/bin/bash
# Copyright (c) 2026 Juan Maria Gomez Lopez <juan-maria.gomez-lopez@tutamail.com>
# SPDX-License-Identifier: MIT

set -euo pipefail

: "${JENKINS_URL:?Missing JENKINS_URL}"
: "${JENKINS_AGENT_NAME:?Missing JENKINS_AGENT_NAME}"
: "${JENKINS_SECRET:?Missing JENKINS_SECRET}"
WORKDIR="${JENKINS_AGENT_WORKDIR:-/home/jenkins/agent}"

echo "Waiting for Jenkins on ${JENKINS_URL}..."
until curl -fsS -o /tmp/agent.jar "${JENKINS_URL%/}/jnlpJars/agent.jar"; do
    sleep 5
done

exec java ${JAVA_OPTS:-} -jar /tmp/agent.jar \
    -url "${JENKINS_URL}" \
    -name "${JENKINS_AGENT_NAME}" \
    -secret "${JENKINS_SECRET}" \
    -workDir "${WORKDIR}" \
    -webSocket

# webSocket -> The agent is connected to port 8080 and it's not needed expose port 50000. If you want TCP, you
# can unset this option and enable port 50000 in security -> agents.