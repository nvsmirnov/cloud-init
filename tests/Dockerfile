ARG BASE_IMAGE=ubuntu:latest
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

# Detect the package manager present in BASE_IMAGE and install the same
# bootstrap prerequisites via whichever one applies. lsb-release is
# apt-only - it's only needed for cc_apt_configure's codename detection.
# bash is explicit for the apk branch - Alpine's base image doesn't
# include it, and this repo's scripts all shebang #!/bin/bash.
RUN set -eu; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && \
      apt-get install -y --no-install-recommends \
        cloud-init \
        git \
        ca-certificates \
        lsb-release && \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v dnf >/dev/null 2>&1; then \
      dnf install -y cloud-init git ca-certificates && \
      dnf clean all; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache cloud-init git ca-certificates bash; \
    else \
      echo "unsupported base image: no known package manager found" >&2; \
      exit 1; \
    fi

COPY stage-runner.sh /usr/local/bin/stage-runner.sh
RUN chmod +x /usr/local/bin/stage-runner.sh

# Amazon Linux ships an AL-specific "selinux" module in cloud_init_modules.
# Inside a container SELinux is unavailable, so sestatus reports no "Current
# mode" and cc_selinux dies with KeyError('current_mode') - that fails
# `cloud-init init` (exit 1) and makes `cloud-init status` report an error,
# even though the bootstrap under test completes fine. Test-harness-only
# fixup, same spirit as the seed dir's `network-config: disabled`. No-op on
# images that don't ship the module (ubuntu/debian/fedora/alpine).
RUN sed -i '/^[[:space:]]*-[[:space:]]*selinux[[:space:]]*$/d' /etc/cloud/cloud.cfg

# /repo-under-test is bind-mounted from the host and owned by the host
# user, not root (which this container runs as) - git's ownership check
# (CVE-2022-24765 mitigation) would otherwise refuse to clone it. git
# matches safe.directory against the discovered .git dir, not the mount
# root, so a wildcard is needed here rather than the exact mount path.
# This is purely a test-harness artifact (ansible-pull on a real machine
# has no such UID mismatch), so it's safe to trust unconditionally here.
RUN git config --system --add safe.directory '*'
