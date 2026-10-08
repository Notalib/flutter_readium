#!/usr/bin/env bash
# Runs on the first boot of a fresh AVD, before android-emulator-runner saves the
# quickboot snapshot that later runs restore. A restore reports sys.boot_completed=1
# at once, so the snapshot must already hold a ready framework (upstream #489).
set -euo pipefail

adb wait-for-device
timeout 300 bash -c 'until adb shell pm path android | grep -q package:; do sleep 2; done' \
  || { echo "package manager not ready" >&2; exit 1; }
# The runner's `input keyevent 82` needs this service; `service check` works on API 24.
timeout 300 bash -c 'until adb shell service check input | grep -q ": found"; do sleep 2; done' \
  || { echo "input service not published" >&2; exit 1; }
# Let post-boot work (package scans, jobs) finish before the snapshot is taken.
sleep 60
echo "AVD snapshot settled"
