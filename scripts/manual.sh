#!/bin/bash

set -euo pipefail

# One-shot manual bootstrap for project cloud-init-ansiblepull for an
# already-installed Linux machine (e.g. a new laptop),
# running ansible-pull directly against this repo's playbook
#
# Usage: curl -sSf --retry 3 -o manual.sh \
#          https://raw.githubusercontent.com/nvsmirnov/cloud-init-ansiblepull/main/scripts/manual.sh \
#          && bash manual.sh
#
# No command-line arguments.
# You may run it with alternative value for ROLES (default is base,extended)
#
# Also you can override REPO_URL (git fetch url), REPO_CHECKOUT (branch)
#
# Cleans up after itself: git/ansible-core packages are purged afterward
# only if this script installed them (packages already present before the
# run, or packages the playbook's roles install, are left alone); any
# packages left orphaned by that purge (e.g. ansible-core's apt/dnf
# Recommends) are also swept up via autoremove, but only if there were zero
# pre-existing orphans before this run started, so pre-existing orphaned
# packages are never touched.
#
# Supports apt-based (Debian/Ubuntu), dnf-based (RHEL-family), and apk-based
# (Alpine) systems, detected via /etc/os-release. Anything else fails loudly
# rather than guessing. See AI-docs/AI-spec.md "Целевые дистрибутивы" for the
# project's broader distro goals.

MYNAME="manual.sh"

export DEBIAN_FRONTEND=noninteractive

REPO_URL="${REPO_URL:-https://github.com/nvsmirnov/cloud-init-ansiblepull.git}"
REPO_CHECKOUT="${REPO_CHECKOUT:-main}"
ROLES="${ROLES:-"base,extended"}"

if [ "$(id -u)" -ne 0 ]; then
  echo "$MYNAME: must run as root" >&2
  exit 1
fi

if [ ! -r /etc/os-release ]; then
  echo "$MYNAME: /etc/os-release not found, cannot detect package manager" >&2
  exit 1
fi
. /etc/os-release
DISTRO_LIKE="${ID_LIKE:-${ID:-}}"

case " $DISTRO_LIKE " in
  *" debian "*)
    PKG_FAMILY=apt
    ;;
  *" rhel "*|*" fedora "*)
    PKG_FAMILY=yum
    if ! command -v dnf >/dev/null 2>&1; then
      echo "$MYNAME: yum-family system without dnf is not supported" >&2
      exit 1
    fi
    ;;
  *" alpine "*)
    PKG_FAMILY=apk
    ;;
  *)
    echo "$MYNAME: not supported: unrecognized distro (ID_LIKE/ID: '$DISTRO_LIKE'), only apt-, dnf- and apk-based systems are supported" >&2
    exit 1
    ;;
esac

pkg_is_installed() {
  case "$PKG_FAMILY" in
    apt) dpkg -s "$1" >/dev/null 2>&1 ;;
    yum) rpm -q "$1" >/dev/null 2>&1 ;;
    apk) apk info -e "$1" >/dev/null 2>&1 ;;
  esac
}

pkg_update() {
  case "$PKG_FAMILY" in
    apt) apt-get update ;;
    yum) : ;; # dnf refreshes repo metadata as needed, no separate step
    apk) apk update ;;
  esac
}

pkg_install() {
  case "$PKG_FAMILY" in
    apt) apt-get install -y "$1" ;;
    yum) dnf install -y "$1" ;;
    apk) apk add "$1" ;;
  esac
}

pkg_purge() {
  case "$PKG_FAMILY" in
    apt) apt-get purge -y "$1" ;;
    yum) dnf remove -y "$1" ;;
    apk) apk del "$1" ;;
  esac
}

# True (empty) when there are currently no orphaned auto-installed packages.
pkg_autoremove_list_empty() {
  case "$PKG_FAMILY" in
    apt) ! apt-get -s autoremove 2>/dev/null | grep -q '^Remv ' ;;
    yum) [ -z "$(dnf -y -q repoquery --unneeded 2>/dev/null)" ] ;;
    apk) true ;; # apk del already removes orphaned deps automatically, nothing separate to check
  esac
}

pkg_autoremove() {
  case "$PKG_FAMILY" in
    apt) SUDO_FORCE_REMOVE=yes apt-get autoremove -y ;;  # if sudo is installed as a dependency, then it is failing to autoremove in container because "no root password has been set"
    yum) dnf autoremove -y ;;
    apk) : ;; # apk del already removes orphaned deps automatically, no separate step
  esac
}

pkg_clean() {
  case "$PKG_FAMILY" in
    apt) apt-get clean ;;
    yum) dnf clean all ;;
    apk) rm -rf /var/cache/apk/* ;;
  esac
}

echo "$MYNAME: checking and installing prerequisites"

GIT_PREINSTALLED=false
if pkg_is_installed git; then
  GIT_PREINSTALLED=true
fi

ANSIBLE_PREINSTALLED=false
if pkg_is_installed ansible-core; then
  ANSIBLE_PREINSTALLED=true
fi

# If there are zero orphaned auto-installed packages before this run, any
# orphans left after it are entirely our own doing, so they are safe to
# autoremove later. If orphans already existed, leave them alone - we can't
# tell which ones are ours.
AUTOREMOVE_WAS_EMPTY=false
if pkg_autoremove_list_empty; then
  AUTOREMOVE_WAS_EMPTY=true
fi

if [ "$GIT_PREINSTALLED" = false ] || [ "$ANSIBLE_PREINSTALLED" = false ]; then
  pkg_update
fi
if [ "$GIT_PREINSTALLED" = false ]; then
  # ansible-pull shells out to git to clone the playbook repo.
  pkg_install git
fi
if [ "$ANSIBLE_PREINSTALLED" = false ]; then
  pkg_install ansible-core
fi

if [ "$PKG_FAMILY" = apk ]; then
  # ansible.builtin.package has no builtin apk support (only apt/dnf ship
  # inside ansible-core) - community.general.apk covers it, but a
  # collection installed mid-play isn't visible to later tasks in that
  # same ansible-pull run, so it has to happen here, before ansible-pull
  # starts, not from inside the playbook.
  echo "$MYNAME: installing ansible-galaxy collection community.general"
  ansible-galaxy collection install community.general
fi

echo "$MYNAME: running ansible-pull"

ANSIBLE_PULL_ARGS=(--url="$REPO_URL" --checkout="$REPO_CHECKOUT")
if [ -n "$ROLES" ]; then
  ANSIBLE_PULL_ARGS+=(-e "roles=$ROLES")
fi
ANSIBLE_PULL_ARGS+=(ansible/playbook.yml)

ansible-pull "${ANSIBLE_PULL_ARGS[@]}"

echo "$MYNAME: ansible-pull done"

if [ "$ANSIBLE_PREINSTALLED" = false ]; then
  echo "$MYNAME: removing ansible-core (was not installed before this run)"
  pkg_purge ansible-core
fi

if [ "$GIT_PREINSTALLED" = false ]; then
  echo "$MYNAME: removing git (was not installed before this run)"
  pkg_purge git
fi

if [ "$AUTOREMOVE_WAS_EMPTY" = true ]; then
  echo "$MYNAME: removing packages orphaned by this run"
  pkg_autoremove
fi

pkg_clean

echo "$MYNAME: done"
