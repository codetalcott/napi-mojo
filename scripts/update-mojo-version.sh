#!/usr/bin/env bash
# Update the pinned Mojo version in pixi.toml
# Usage: ./scripts/update-mojo-version.sh 0.27.0.0.dev2026040102
#
# Nightly changelog (check after bumping if the build breaks):
#   https://mojolang.org/releases/nightly/
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <mojo-version>"
  echo "Example: $0 0.27.0.0.dev2026040102"
  exit 1
fi

NEW_VERSION="$1"
sed -i.bak "s/mojo = \"==.*/mojo = \"==$NEW_VERSION\"/" pixi.toml
rm -f pixi.toml.bak
echo "Updated pixi.toml to mojo == $NEW_VERSION"
pixi install
