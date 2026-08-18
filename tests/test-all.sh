#!/bin/bash

# run tests on all supported platforms

set -euo pipefail

cd "$(dirname -- "$0")"

NO_STOP_ON_FIRST_FAIL="${NO_STOP_ON_FIRST_FAIL:-}"

SUPPORTED_IMAGES=(
  amazonlinux:latest
  alpine:latest
  debian:latest
  ubuntu:latest
  fedora:latest
)

IMAGES_PASSED=()
IMAGES_FAILED=()

for IMAGE in "${SUPPORTED_IMAGES[@]}"; do
  echo "========================================================================"
  echo "Pulling $IMAGE"
  docker pull "$IMAGE"
  echo "Running test on $IMAGE..."
  RV=0; time BASE_IMAGE="$IMAGE" ./run.sh || RV=$?
  echo "========================================================================"
  if [ "$RV" != 0 ]; then
    echo "FAILED: ${IMAGE}"
    IMAGES_FAILED+=("$IMAGE")
    if [ -z "$NO_STOP_ON_FIRST_FAIL" ]; then
      echo "aborting (set NO_STOP_ON_FIRST_FAIL to run all tests anyway)"
      break
    fi
  else
    echo "PASSED: ${IMAGE}"
    IMAGES_PASSED+=("$IMAGE")
  fi
done

echo "========================================================================"

if [ -z "${IMAGES_PASSED[*]}" ]; then
  echo "No image passed test"
else
  echo "images passed test:"
  for IMAGE in "${IMAGES_PASSED[@]}"; do
    echo "  $IMAGE"
  done
fi

if [ -z "${IMAGES_FAILED[*]}" ]; then
  echo "No failed images (ok!)"
else
  echo "images FAILED test:"
  for IMAGE in "${IMAGES_FAILED[@]}"; do
    echo "  $IMAGE"
  done
  echo "ERROR: There were failed images, see above"
  exit 1
fi
