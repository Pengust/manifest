#!/bin/bash
# Take the pinned AOSP projects, sparse patterns and patches from a Rust OS
# checkout (its android/tree/, which lean.sh makes from a build).
# usage: ./update.sh RUSTOS_DIR
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(cd "${1:?usage: update.sh RUSTOS_DIR}/android/tree" && pwd)
cp "$T/manifest.xml" "$HERE/aosp.xml"
rm -rf "$HERE/sparse" "$HERE/patches"
cp -r "$T/sparse" "$T/patches" "$HERE/"
echo "$(grep -c '<project' "$HERE/aosp.xml") AOSP projects"
