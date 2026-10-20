# Copyright (c) 2026 Juan Maria Gomez Lopez <juan-maria.gomez-lopez@tutamail.com>
# SPDX-License-Identifier: MIT

# Jenkins' agent.jar needs Java 17+ and stretch only ships Java 8, so the Java
# runtime and the (static) Docker CLI are taken from upstream images instead of apt.
FROM eclipse-temurin:21-jre AS java
FROM docker:29-cli AS docker-cli

FROM debian:stretch

ARG DEBIAN_FRONTEND=noninteractive
ARG AGENT_UID=1002
ARG AGENT_GID=1002

# Stretch is end-of-life and only available on archive.debian.org, whose Release
# files have expired: point apt there and skip the Valid-Until check.
RUN printf '%s\n' \
        'deb http://archive.debian.org/debian stretch main' \
        'deb http://archive.debian.org/debian-security stretch/updates main' \
        > /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

# Toolchain C/C++
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git openssh-client \
        build-essential gcc g++ gdb make cmake ninja-build \
        clang clang-format clang-tidy lldb \
        autoconf automake libtool pkg-config \
        ccache valgrind cppcheck python3 fakeroot rsync wget \
    && rm -rf /var/lib/apt/lists/*

# Install qt5 base from Debian 9 repositories
RUN apt-get update && apt-get install -y --no-install-recommends \
        libqt5core5a libqt5network5 qtbase5-dev \
        libqt5sql5-psql libqt5sql5-sqlite libqt5sql5 \
    && rm -rf /var/lib/apt/lists/*

# Install libcurl
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-gnutls-dev \
    && rm -rf /var/lib/apt/lists/*

# libcurlpp-dev is not packaged for stretch (it arrived in buster): build curlpp
# from source into /usr/local. BuildKit downloads and verifies the tarball, since
# stretch's own TLS stack is too old to rely on.
ADD --checksum=sha256:97e3819bdcffc3e4047b6ac57ca14e04af85380bd93afe314bee9dd5c7f46a0a \
    https://github.com/jpbarrette/curlpp/archive/refs/tags/v0.8.1.tar.gz /tmp/curlpp.tar.gz
RUN tar xzf /tmp/curlpp.tar.gz -C /tmp \
    && mkdir /tmp/curlpp-0.8.1/build && cd /tmp/curlpp-0.8.1/build \
    && cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. \
    && make -j"$(nproc)" && make install && ldconfig \
    && sed -i 's/^Version:.*/Version: 0.8.1/' /usr/local/lib/pkgconfig/curlpp.pc \
    && rm -rf /tmp/curlpp.tar.gz /tmp/curlpp-0.8.1

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

# User jenkins can create and modify in /opt
chgrp jenkins /opt
chmod 2775 /opt

# Shared by all agents: the "common" build context is agent_jenkins_common/ (see docker-compose.yml)
COPY --from=common --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENV CCACHE_DIR=/home/jenkins/.ccache \
    PATH=/usr/lib/ccache:${JAVA_HOME}/bin:${PATH}

USER jenkins

WORKDIR /home/jenkins
# PID 1 init (tini) comes from `init: true` in docker-compose.yml
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
