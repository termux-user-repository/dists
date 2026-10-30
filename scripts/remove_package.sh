#!/usr/bin/env bash
set -e -o pipefail

## Remove a package from the repository WITHOUT re-signing anything.
##
## This only drops the package entries:
##   - pool/<component>/<pkg>_<version>_<arch>.deb metadata stubs
##   - the matching stanzas in dists/.../binary-*/Packages(.gz), which are
##     regenerated from the remaining pool stubs the same way
##     dist_handler.sh does
## Release/InRelease/Release.gpg are intentionally left untouched; the
## auto-build pipeline re-signs dists on its next run. Trigger it manually
## (workflow_dispatch) right after pushing to minimize the window in which
## the Release checksums do not match the regenerated indexes.
##
## Usage: scripts/remove_package.sh <package-name> [component]

BASE_DIR=$(realpath "$(dirname "$BASH_SOURCE")")
POOL_DIR="$(dirname "$BASE_DIR")/pool"
DISTS_DIR="$(dirname "$BASE_DIR")/dists"
REPO_JSON="$(dirname "$BASE_DIR")/repo.json"

arch_array=("aarch64" "arm" "i686" "x86_64")
all_components=($(jq -r '.[].name' "$REPO_JSON"))

usage() {
    echo "Usage: $(basename "$0") <package-name> [component]" >&2
    echo "  <package-name>  exact package name (e.g. foo, not foo-static)" >&2
    echo "  [component]     optional: one of: ${all_components[*]}" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
package_name="$1"

name_re='^[a-zA-Z0-9][a-zA-Z0-9.+~-]*$'
if [[ ! "$package_name =~ $name_re" ]]; then
    echo "invalid package name: $package_name" >&2
    exit 2
fi

if [[ $# -eq 2 ]]; then
    components=("$2")
    if ! printf '%s\n' "${all_components[@]}" | grep -qx "$2"; then
        echo "unknown component: $2 (known: ${all_components[*]})" >&2
        exit 2
    fi
else
    components=("${all_components[@]}")
fi

removed_stubs=()
updated_indexes=()
for comp in "${components[@]}"; do
    pool_comp_dir="$POOL_DIR/$comp"
    [[ -d "$pool_comp_dir" ]] || continue

    shopt -s nullglob
    stubs=("$pool_comp_dir/${package_name}_"*.deb)
    shopt -u nullglob
    if [[ ${#stubs[@]} -eq 0 ]]; then
        continue
    fi

    echo "[$comp] removing pool entries:"
    printf '  %s\n' "${stubs[@]##*/}"
    rm -f "${stubs[@]}"
    removed_stubs+=("${stubs[@]##*/}")

    ## Regenerate the Packages indexes from the remaining pool entries,
    ## mirroring create_packages() in dist_handler.sh, so the removed
    ## package disappears from dists without touching the signatures.
    pushd "$pool_comp_dir" >/dev/null
    for suite_dir in "$DISTS_DIR"/*/; do
        [[ -d "$suite_dir" ]] || continue
        for arch in "${arch_array[@]}"; do
            packages_file="${suite_dir}${comp}/binary-${arch}/Packages"
            [[ -f "$packages_file" ]] || continue
            cat ./*{$arch,all}.deb 2>/dev/null >| "$packages_file" || true
            gzip -9nkf "$packages_file"
            updated_indexes+=("$packages_file")
        done
    done
    popd >/dev/null
done

if [[ ${#removed_stubs[@]} -eq 0 ]]; then
    echo "no pool entry found for package: $package_name" >&2
    exit 1
fi

echo
echo "removed ${#removed_stubs[@]} pool entry(ies) for '$package_name'"
echo "regenerated indexes:"
printf '  %s\n' "${updated_indexes[@]}"

## Hint about related packages (e.g. <pkg>-static, <pkg>-data) that are
## still around; they are separate packages and must be removed explicitly.
shopt -s nullglob
related=()
for comp in "${components[@]}"; do
    for stub in "$POOL_DIR/$comp/${package_name}-"*; do
        related+=("$comp/${stub##*/}")
    done
done
shopt -u nullglob
if [[ ${#related[@]} -gt 0 ]]; then
    echo
    echo "note: related packages are still present, remove them explicitly if intended:"
    printf '  %s\n' "${related[@]}"
fi

echo
echo "Signatures were NOT updated. Next steps:"
echo "  1. git add pool dists && git commit -m 'Remove $package_name' && git push"
echo "  2. trigger the auto-build workflow (workflow_dispatch) to re-sign dists"
