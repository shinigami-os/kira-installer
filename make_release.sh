#!/bin/sh
# Usage: ./make_release.sh <version>
set -e

VERSION="${1:?usage: ./make_release.sh <version>}"

echo "Building the installer ISO..."
sudo make clean && sudo make iso
echo "=========================== Saving the installer ISO... ==========================="
../kira-base/scripts/push-iso-release.sh "$VERSION"

echo ""
echo "Done ! "
