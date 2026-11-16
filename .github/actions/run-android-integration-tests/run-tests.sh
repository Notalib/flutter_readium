#!/usr/bin/env bash
# Runs the example app's integration suite on the booted emulator, from flutter_readium/example.
# Usage: run-tests.sh <api-level>. Writes the files the workflow uploads on failure.
set -uo pipefail

api_level=$1
test_log="$GITHUB_WORKSPACE/android-test-api$api_level.log"
logcat_file="$GITHUB_WORKSPACE/android-logcat-api$api_level.txt"
# Must match applicationId in example/android/app/build.gradle.kts.
app_id=com.example.flutter_readium_example
# flutter test runs `adb -s <serial> install -t -r <apk>`. It takes ~11 s when healthy, but on the
# API 24 emulator it sometimes never returns.
install_pattern='adb -s [^ ]+ install '
install_limit_s=120
hang_marker=$(mktemp -u)

# Kills a hung `adb install`, so flutter test fails fast instead of eating the job's time limit.
watch_install() {
  local waited=0
  while sleep 5; do
    if pgrep -f "$install_pattern" > /dev/null; then waited=$((waited + 5)); else waited=0; fi
    if [ "$waited" -ge "$install_limit_s" ]; then
      echo "::warning::adb install hung for ${waited}s on API $api_level; killing it"
      touch "$hang_marker"
      pkill -f "$install_pattern"
      waited=0
    fi
  done
}

capture_hang_diagnostics() {
  {
    echo "=== adb install hang, attempt $1 ==="
    timeout 30s adb devices -l
    timeout 30s adb shell getprop sys.boot_completed
    timeout 60s adb logcat -d -v threadtime
  } >> "$logcat_file" 2>&1
  # The logcat file is uploaded only when the job fails, so show the likely culprits here too.
  grep -E ' (PackageManager|PackageInstaller|installd|dex2oat)' "$logcat_file" | tail -n 100
}

for attempt in 1 2; do
  rm -f "$hang_marker"
  watch_install &
  watcher=$!
  # Kept well under the job's 30-minute limit, so a hang still ends here with logcat captured.
  timeout 15m flutter test integration_test/plugin_integration_test.dart --timeout=300s \
    --dart-define=READIUM_TEST_SKIP_LOGS=true 2>&1 | tee -a "$test_log"
  status=$?
  kill "$watcher"
  [ "$status" -eq 0 ] && exit 0

  # Any other failure is real and must stand, with the app's own logcat.
  if [ ! -e "$hang_marker" ]; then
    app_pid=$(timeout 10s adb shell pidof -s "$app_id" | tr -d '\r')
    timeout 60s adb logcat -d -v threadtime ${app_pid:+--pid="$app_pid"} >> "$logcat_file" 2>&1
    exit 1
  fi

  capture_hang_diagnostics "$attempt"
  if [ "$attempt" -eq 1 ]; then
    echo "::warning::Restarting adb and retrying the integration suite on API $api_level"
    adb kill-server
    timeout 60s adb wait-for-device
  fi
done
exit 1
