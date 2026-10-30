#!/usr/bin/env bash
set -e -o pipefail
echo "Jai ho"
base_dir=$(realpath "$(dirname "$0")")

# Always rebuild and re-sign dists from the current pool state.
# Pending .tar assets only decide whether new packages are added; the
# rebuild itself must not depend on them, otherwise manual edits to
# pool/ or dists/ would keep serving stale signatures and break the repo.
if ! "$base_dir/dist_handler.sh"; then
    echo "dist_handler failed" >&2
    exit 1
fi

"$base_dir/remote_handler.sh"
