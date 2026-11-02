#!/usr/bin/env bash
# Use this wrapper for Flutter commands that regenerate native plugin metadata.
# Do not change the user's global Flutter settings or the app's pubspec.
set -euo pipefail
export FLUTTER_SWIFT_PACKAGE_MANAGER=false
exec flutter "$@"
