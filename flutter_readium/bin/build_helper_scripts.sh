#!/bin/bash

set -e

# Set ROOT to the folder where this script is located
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Set the path to the Readium JS scripts folder
READIUM_SCRIPTS_FOLDER="$ROOT/assets/_helper_scripts"

watch_mode=false

for arg in "$@"; do
  if [ "$arg" == "-w" ]; then
    watch_mode=true
    break
  fi
done

cd $READIUM_SCRIPTS_FOLDER

npm i

if [ "$watch_mode" = true ]; then
  npm run watch
else
  npm run build:flutter
fi
