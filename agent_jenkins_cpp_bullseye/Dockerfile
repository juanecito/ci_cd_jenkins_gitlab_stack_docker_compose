# Copyright (c) 2026 Juan Maria Gomez Lopez <juan-maria.gomez-lopez@tutamail.com>
# SPDX-License-Identifier: MIT

# Jenkins' agent.jar needs Java 17+ and bullseye is archived (no more updates to its
# openjdk-17), so the Java runtime and the (static) Docker CLI are taken from upstream
# images instead of apt.
FROM eclipse-temurin:21-jre AS java
FROM docker:29-cli AS docker-cli

FROM debian:bullseye

ARG DEBIAN_FRONTEND=noninteractive
ARG AGENT_UID=1002
ARG AGENT_GID=1002

# Bullseye's LTS ended in August 2026 and it moved to archive.debian.org (the
# security pool on deb.debian.org now returns 404): point apt there and skip the
# Valid-Until check.
RUN printf '%s\n' \
        'deb http://archive.debian.org/debian bullseye main' \
        'deb http://archive.debian.org/debian bullseye-updates main' \
        'deb http://archive.debian.org/debian-security bullseye-security main' \
        > /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

# Toolchain C/C++
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git openssh-client \
        build-essential gcc g++ gdb make cmake ninja-build \
        clang clang-format clang-tidy lld lldb \
        autoconf automake libtool pkg-config \
        ccache valgrind cppcheck python3 \
    && rm -rf /var/lib/apt/lists/*

# Install qt5 base from Debian 11 repositories
RUN apt-get update && apt-get install -y --no-install-recommends \
        libqt5core5a libqt5network5 qtbase5-dev \
        libqt5sql5-psql libqt5sql5-sqlite libqt5sql5 \
    && rm -rf /var/lib/apt/lists/*

# Install libcurl
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-gnutls-dev libcurlpp-dev \
    && rm -rf /var/lib/apt/lists/*

# Install tools deb packages generation
RUN apt-get update && apt-get install -y --no-install-recommends \
        file dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# Install libpq (Postgresql link)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install apt-pkg dev
RUN apt-get update && apt-get install -y --no-install-recommends \
        libapt-pkg-dev \
    && rm -rf /var/lib/apt/lists/*

# Java 21 (for Jenkins agent)
ENV JAVA_HOME=/opt/java/openjdk
COPY --from=java ${JAVA_HOME} ${JAVA_HOME}

# Docker CLI + Buildx + Compose
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

# User Jenkins
RUN groupadd -g ${AGENT_GID} jenkins \
    && useradd -m -u ${AGENT_UID} -g jenkins -s /bin/bash jenkins \
    && mkdir -p /home/jenkins/agent /home/jenkins/.ccache \
    && chown -R jenkins:jenkins /home/jenkins

# Shared by all agents: the "common" build context is agent_jenkins_common/ (see docker-compose.yml)
COPY --from=common --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENV CCACHE_DIR=/home/jenkins/.ccache \
    PATH=/usr/lib/ccache:${JAVA_HOME}/bin:${PATH}

USER jenkins

WORKDIR /home/jenkins
# PID 1 init (tini) comes from `init: true` in docker-compose.yml
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
