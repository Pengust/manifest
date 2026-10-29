#!/bin/bash
# Check out the tree after `repo init` (README.md): fetch everything, check
# the big prebuilts out sparsely, apply Rust OS's patches to AOSP, and hide
# rustos/ from Soong.
# usage: .repo/manifests/prepare.sh [JOBS]
set -e
M=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$M/../.." && pwd)
J=${1:-16}
cd "$TOP"

# commits and trees first: the checkout comes after the sparse patterns
repo sync -n -c --no-tags --no-clone-bundle -j"$J"

# the big prebuilts keep only what the build uses (one Clang, the SDK
# levels in use...)
for list in "$M"/sparse/*.txt; do
	project=$(sed -n '1s/^# \([^:]*\):.*/\1/p' "$list")
	gitdir=.repo/projects/$project.git
	git --git-dir="$gitdir" config core.sparseCheckout true
	git --git-dir="$gitdir" config core.sparseCheckoutCone false
	mkdir -p "$gitdir/info"
	grep -v '^#' "$list" > "$gitdir/info/sparse-checkout"
	# a tree checked out before: its checkout follows the patterns now
	if [ -d "$project" ]; then
		git -C "$project" sparse-checkout reapply
	fi
done
repo sync -l -c -j"$J"

# Rust OS's changes to AOSP projects: patches/<project path, / as _>/
for dir in "$M"/patches/*/; do
	project=$(basename "$dir" | tr _ /)
	for patch in "$dir"*.patch; do
		# already there when preparing again
		subject=$(sed -n 's/^Subject: \(\[PATCH[^]]*\] \)\{0,1\}//p' "$patch" | head -1)
		git -C "$project" log -50 --format=%s | grep -qxF "$subject" && continue
		git -C "$project" am -q --keep-cr "$patch"
	done
done

# Soong reads every Android.bp under the top; the products in rustos/ are
# copied into device/ by the build, so it must not see them twice
touch rustos/.find-ignore

echo "tree ready in $TOP: $(du -sh --exclude=.repo . | cut -f1) checked out, $(du -sh .repo | cut -f1) in git"
