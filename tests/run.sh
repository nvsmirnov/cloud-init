#!/bin/bash

set -euo pipefail

# Smoke-test a user-data template against the real cloud-init binary in
# Docker: no systemd, no --privileged, no VM. Builds a NoCloud seed dir
# from the real template (url rewritten to a local bind mount, so the
# test needs no network access) and runs the boot stages manually.

TEMP_DIR=""
cleanup() {
  local DIR
  if [ -z "${NO_CLEANUP:-}" ]; then
    for DIR in "$TEMP_DIR"; do
      [ -n "${DEBUG:-}" ] && echo "$0: cleanup(): rm -rf $DIR"
      [ -n "$DIR" ] && rm -rf "$DIR"
    done
  fi
}
trap cleanup EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="${1:-user-data/test-all.yaml}"
TEMPLATE_FILE_FULL_PATH="$REPO_ROOT/$TEMPLATE_FILE"
BASE_IMAGE="${BASE_IMAGE:-ubuntu:latest}"
IMAGE_TAG="cloud-init-ansiblepull-smoke-test:$(echo "$BASE_IMAGE" | tr ':/' '--')"

if [ ! -f "$TEMPLATE_FILE_FULL_PATH" ]; then
  echo "user-data template not found: $TEMPLATE_FILE_FULL_PATH" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
SEED_DIR="$TEMP_DIR/seed"
SCRATCH_REPO="$TEMP_DIR/repo-snapshot"
mkdir -p "$SEED_DIR" "$SCRATCH_REPO"
cp "$REPO_ROOT/tests/seed-template/meta-data" "$SEED_DIR/meta-data"
cp "$REPO_ROOT/tests/seed-template/network-config" "$SEED_DIR/network-config"

# Point the real template's ansible-pull --url at the local bind-mounted
# repo instead of GitHub, so the test needs no network access.
sed -E 's#--url=[^ ]+#--url=file:///repo-under-test#' \
  "$TEMPLATE_FILE_FULL_PATH" > "$SEED_DIR/user-data"

# ansible-pull does a real "git clone", which only ever sees committed
# objects - it can't see uncommitted or untracked changes no matter what.
# So snapshot exactly what "git add -A && git commit" would capture right
# now (tracked + untracked-but-not-ignored files) into a disposable,
# one-commit repo, and point ansible-pull at that instead of $REPO_ROOT.
# This never touches the real repo's branches/refs/history.
( cd "$REPO_ROOT" && git ls-files -z --cached --others --exclude-standard ) \
  | rsync -a --files-from=- --from0 "$REPO_ROOT/" "$SCRATCH_REPO/"

# The template's --checkout=<branch> still has to resolve to something in
# the snapshot repo, so create the one commit on a branch named after
# whatever the template asks for.
CHECKOUT_BRANCH="$(grep -oE -- '--checkout=[^ ]+' "$TEMPLATE_FILE_FULL_PATH" | head -n1 | cut -d= -f2)"
CHECKOUT_BRANCH="${CHECKOUT_BRANCH:-main}"

(
  cd "$SCRATCH_REPO"
  git init -q -b "$CHECKOUT_BRANCH"
  git add -A
  git -c user.email=smoke-test@localhost -c user.name=smoke-test \
    commit -q -m "smoke-test snapshot of working tree"
)

docker build --build-arg BASE_IMAGE="$BASE_IMAGE" -t "$IMAGE_TAG" "$REPO_ROOT/tests"

docker run --rm \
  -v "$SEED_DIR:/var/lib/cloud/seed/nocloud:ro" \
  -v "$SCRATCH_REPO:/repo-under-test:ro" \
  "$IMAGE_TAG" \
  /usr/local/bin/stage-runner.sh
