#!/bin/bash
# Take the pinned AOSP projects and sparse patterns from a Rust OS
# checkout (its android/tree/, which lean.sh makes from a build).
# usage: ./update.sh RUSTOS_DIR
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(cd "${1:?usage: update.sh RUSTOS_DIR}/android/tree" && pwd)
cp "$T/manifest.xml" "$HERE/aosp.xml"
rm -rf "$HERE/sparse"
cp -r "$T/sparse" "$HERE/"
echo "$(grep -c '<project' "$HERE/aosp.xml") AOSP projects"
