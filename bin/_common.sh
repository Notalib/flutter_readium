# shellcheck shell=bash
#
# Shared bootstrap for bin/ scripts. Source it as the FIRST line of each script:
#
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
#
# Goal: make every script safe to run from any working directory and from a
# non-interactive, non-login shell (CI runners and AI-agent sandboxes), which
# do NOT source a developer's ~/.bashrc / ~/.zshrc and therefore lack the PATH
# entries a normal terminal would have.
#
# Not meant to be executed directly.

# Fail loudly and early. Deliberately NOT using `-u` (nounset): several scripts
# (e.g. forAll) intentionally test unset positional args like `[ "x$1" = "x" ]`.
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# --- PATH: add standard, broadly-portable locations -------------------------
# Only prepend dirs that exist and aren't already present. This does NOT assume
# any particular toolchain manager — it just surfaces the usual install spots so
# an existing flutter/dart/node is found in a bare shell.
_prepend_path() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;            # already present
    *) PATH="$1:$PATH" ;;
  esac
}
_prepend_path "/opt/homebrew/bin"        # Homebrew (Apple Silicon)
_prepend_path "/usr/local/bin"           # Homebrew (Intel) / common installs
_prepend_path "$HOME/.pub-cache/bin"     # globally-activated Dart tools
# node/npm via nvm, newest installed version, if nvm is used — but only when npm
# isn't already resolvable. This avoids overriding a newer system/Homebrew npm
# with an older nvm-bundled one (npm <11.15.0 rejects min-release-age + --before
# together; fixed in npm 11.15.0 via https://github.com/npm/cli/pull/9339).
if ! command -v npm >/dev/null 2>&1 && [ -d "$HOME/.nvm/versions/node" ]; then
  _nvm_bin="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)"
  [ -n "${_nvm_bin:-}" ] && _prepend_path "$_nvm_bin"
fi
export PATH

# --- Toolchain: the Flutter SDK pinned in .flutter-version ------------------
# A flutter on PATH that matches the pin is left alone. Otherwise we look for
# the pinned version in the fvm project symlinks and the fvm cache; a fresh git
# worktree has no .fvm symlink, so the cache lookup is what makes it work there.
# We add the SDK's REAL binaries to PATH (not a `fvm` function shim): real
# binaries are inherited by every child process through the exported PATH, and
# — unlike `export -f` shims — they cannot recurse when fvm itself shells out
# to invoke dart/flutter.

# Prints the Flutter version of the SDK whose bin/ directory is $1. Reads the
# SDK's version stamp instead of running `flutter --version`, which is slow.
# Prints nothing for an SDK that has never run.
_flutter_sdk_version() {
  [ -f "$1/cache/flutter.version.json" ] || return 0
  sed -n 's/.*"flutterVersion": *"\([^"]*\)".*/\1/p' "$1/cache/flutter.version.json"
}

_flutter_pin=""
[ -f "$REPO_ROOT/.flutter-version" ] && _flutter_pin="$(tr -d '[:space:]' <"$REPO_ROOT/.flutter-version")"
_path_flutter_bin=""
_path_flutter_version=""
if command -v flutter >/dev/null 2>&1; then
  _path_flutter_bin="$(dirname "$(command -v flutter)")"
  _path_flutter_version="$(_flutter_sdk_version "$_path_flutter_bin")"
fi

if [ -z "$_path_flutter_bin" ] || ! command -v dart >/dev/null 2>&1 ||
  { [ -n "$_flutter_pin" ] && [ "$_path_flutter_version" != "$_flutter_pin" ]; }; then
  _pinned_sdk_found=""
  for _sdk_bin in \
    "$REPO_ROOT/flutter_readium/.fvm/flutter_sdk/bin" \
    "$REPO_ROOT/.fvm/flutter_sdk/bin" \
    "${FVM_CACHE_PATH:-$HOME/fvm}/versions/$_flutter_pin/bin"; do
    [ -x "$_sdk_bin/dart" ] && [ -x "$_sdk_bin/flutter" ] || continue
    # An fvm symlink left over from before a pin bump points at the old SDK.
    _sdk_version="$(_flutter_sdk_version "$_sdk_bin")"
    if [ -z "$_sdk_version" ] || [ "$_sdk_version" = "$_flutter_pin" ]; then
      # Not _prepend_path: the SDK must come first even if already on PATH.
      PATH="$_sdk_bin:$PATH"
      _pinned_sdk_found=1
      break
    fi
  done
  if [ -z "$_pinned_sdk_found" ] && [ -n "$_path_flutter_version" ]; then
    echo "WARNING: flutter $_path_flutter_version is on PATH but this repo pins $_flutter_pin (.flutter-version)." >&2
    echo "         Results may differ from CI. Install the pinned SDK with: fvm install" >&2
  fi
  export PATH
fi
