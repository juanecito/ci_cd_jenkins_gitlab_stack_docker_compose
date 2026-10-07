# Copyright (c) 2026 Juan Maria Gomez Lopez <juan-maria.gomez-lopez@tutamail.com>
# SPDX-License-Identifier: MIT

FROM debian:trixie

ARG DEBIAN_FRONTEND=noninteractive
ARG AGENT_UID=1002
ARG AGENT_GID=1002

# Java (for Jenkins agent) + toolchain C/C++
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg git openssh-client tini \
        openjdk-21-jre-headless \
        build-essential gcc g++ gdb make cmake ninja-build \
        clang clang-format clang-tidy lld lldb \
        autoconf automake libtool pkg-config \
        ccache valgrind cppcheck python3 \
    && rm -rf /var/lib/apt/lists/*


# Install qt5 base from Debian 13 repositories 
RUN apt-get update && apt-get install -y --no-install-recommends \
        libqt5core5t64 libqt5network5t64 qtbase5-dev \
        libqt5sql5-psql libqt5sql5-sqlite libqt5sql5t64 \
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

# Docker CLI + Buildx + Compose (repo official docker)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# User Jenkins
RUN groupadd -g ${AGENT_GID} jenkins \
    && useradd -m -u ${AGENT_UID} -g jenkins -s /bin/bash jenkins \
    && mkdir -p /home/jenkins/agent /home/jenkins/.ccache \
    && chown -R jenkins:jenkins /home/jenkins

# COPY --chmod=644 daemon.json /etc/docker/daemon.json

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENV CCACHE_DIR=/home/jenkins/.ccache \
    PATH=/usr/lib/ccache:${PATH}

 # it will work with root
USER jenkins

WORKDIR /home/jenkins
ENTRYPOINT [ "/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh" ]