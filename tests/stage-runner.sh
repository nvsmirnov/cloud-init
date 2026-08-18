#!/bin/bash

set -euo pipefail

# Runs inside the smoke-test container. Manually invokes the boot stages
# that systemd units (cloud-init-local.service, cloud-init.service,
# cloud-config.service, cloud-final.service) would normally trigger.
# ansible-core is installed via packages: (final stage) and ansible-pull is
# run via runcmd: (also executed in the final stage, by scripts_user), so
# --mode=final is required.

MARKER_FILE=/var/lib/cloud-init-ansiblepull/all-done

cloud-init init --local
cloud-init init
cloud-init modules --mode=config
cloud-init modules --mode=final

echo "=== cloud-init status ==="
set +e
STATUS_OUTPUT="$(cloud-init status --long)"
STATUS_RC=$?
set -e
echo "$STATUS_OUTPUT"
# exit 1 = hard error, exit 2 = degraded/warnings-only, exit 0 = clean.
# Only exit 1 is treated as a real failure here.
if [ "$STATUS_RC" -eq 1 ]; then
  echo "FAIL: cloud-init status reports a hard error" >&2
  exit 1
fi

echo "=== marker file check ==="
if [ ! -f "$MARKER_FILE" ]; then
  echo "FAIL: $MARKER_FILE not found, playbook did not run" >&2
  exit 1
fi
cat "$MARKER_FILE"

echo "=== idempotency check (re-run the same runcmd script) ==="
RUNCMD_SCRIPT="$(find /var/lib/cloud/instances/*/scripts/runcmd -type f | head -n1)"
if [ -z "$RUNCMD_SCRIPT" ]; then
  echo "FAIL: cloud-init's generated runcmd script not found" >&2
  exit 1
fi
RERUN_OUTPUT="$(bash "$RUNCMD_SCRIPT" 2>&1)"
echo "$RERUN_OUTPUT"
if ! echo "$RERUN_OUTPUT" | grep -qE 'changed=0.*failed=0'; then
  echo "FAIL: ansible-pull re-run reported changes or failures" >&2
  exit 1
fi

echo "SMOKE TEST PASSED"
