#!/usr/bin/env bash
set -e -o pipefail
BASE_DIR=$(realpath "$(dirname "$BASH_SOURCE")")
DEB_DIR=$BASE_DIR/processed_deb
POOL_DIR="$(dirname "$BASE_DIR")/pool"
owner="termux-user-repository"
repo="dists"
tag="0.1"
dists_owner="tur-dists"
dists_template_repo="tur-dists/package-template"

repo_ready() {
    local full_repo="$1"
    local repo_readme_url="https://api.github.com/repos/$full_repo/contents/README.md"

    if gh repo view "$full_repo" >/dev/null 2>&1 && \
        [[ "$(curl -s "$repo_readme_url" | jq -r '.name')" == "README.md" ]]; then
        return 0
    else
        return 1
    fi
}

wait_for_repo_ready() {
    local full_repo="$1"
    local attempt

    for attempt in $(seq 1 30); do
        if repo_ready "$full_repo"; then
            return 0
        fi
        sleep 2
    done

    echo "repo is not ready after retries: $full_repo"
    return 1
}

ensure_dists_repo_exists() {
    local package_name="$1"
    local full_repo="$dists_owner/$package_name"
	sleep 1
    if gh repo view "$full_repo" >/dev/null 2>&1; then
        return
    fi
    echo "creating repo from template: $full_repo"
	sleep 1
    gh repo create "$full_repo" --template "$dists_template_repo" --public
    wait_for_repo_ready "$full_repo"
}

normalize_release_version() {
    local version="$1"
    printf '%s' "${version//:/.}"
}

create_release_if_missing() {
    local repo_name="$1"
    local tag_name="$2"
    local output

    if gh release view -R "$repo_name" "$tag_name" >/dev/null 2>&1; then
        return 0
    fi

    if output=$(gh release create -R "$repo_name" "$tag_name" -n "$tag_name" 2>&1); then
        return 0
    fi

    if echo "$output" | grep -Eqi 'already exists|tag .* already exists'; then
        echo "release already exists: $tag_name"
        return 0
    fi

    echo "$output" >&2
    return 1
}

upload_deb_to_dists_repo() {
    local deb_name="$1"
    local package_name
    local package_version
    local release_version
    package_name="$(echo "$deb_name" | cut -d '_' -f 1)"
    package_version="$(echo "$deb_name" | cut -d '_' -f 2)"
    release_version="$(normalize_release_version "$package_version")"

    if [[ -z "$package_name" || -z "$release_version" ]]; then
        echo "skip invalid deb filename: $deb_name"
        return 0
    fi

    ensure_dists_repo_exists "$package_name"
	sleep 1
    if ! create_release_if_missing "github.com/$dists_owner/$package_name" "$release_version"; then
        echo "$deb_name failed to create release for $dists_owner/$package_name:$release_version"
        return 1
    fi
	sleep 1
    if ! gh release upload -R "github.com/$dists_owner/$package_name" "$release_version" "$deb_name" --clobber; then
        echo "$deb_name issues while uploading to $dists_owner/$package_name:$release_version"
    fi
}

## fetch remote pool for debfile name
fetch_remote_deb_list() {
    api_json=$(mktemp /tmp/repo.XXXXXXX)
    remote_deb_list=$(mktemp /tmp/remote.XXXXXXX)
    echo "fetching release json"
    gh api  \
	    -H "Accept: application/vnd.github.v3+json" \
	     https://api.github.com/repos/${owner}/${repo}/releases > $api_json

    jq -r '.[] | select(.tag_name=="0.1") | .assets[].name' $api_json > $remote_deb_list
}
## genetate local deb file lst
generate_local_deb_list() {
    pushd $POOL_DIR
    local_deb_list=$(mktemp /tmp/local.XXXXXXXX)
    find . -type f -exec basename '{}' \; > $local_deb_list
    sed -i 's/[^\a-zA-Z0-9._+-]/./g' $local_deb_list
    popd
}
## List non_upload debs
## it will create list of those debs which is processed by dist_handler but not uploaded on gh release. 

list_non_upload_debs() {
    echo "listing non-uploaded debs"
    fetch_remote_deb_list
    generate_local_deb_list
    non_uploaded_list=$(mktemp /tmp/non_upl.XXXXXXXXX)
    
    grep -vf $remote_deb_list $local_deb_list | uniq > $non_uploaded_list
}

upload_debs() {
    # list_non_upload_debs
    non_uploaded_list=$(mktemp /tmp/non_upl.XXXXXXXXX)
    updated_packages=""

    mkdir -p "$DEB_DIR"
    # nullglob: with no new deb to upload, skip the rename loop instead of
    # iterating over the literal "*.deb" string.
    shopt -s nullglob
    pushd $DEB_DIR
    for deb in *.deb; do
        modified_name="$(echo "$deb" | sed 's/[^\a-zA-Z0-9._+-]/./g')"
        mv -n "$deb" "$modified_name"
        echo "$modified_name" >> $non_uploaded_list
    done
    shopt -u nullglob
    for deb_name in $(cat $non_uploaded_list); do
        local package_name_tag=$(echo $deb_name | cut -d '_' -f 1)
        # deduplicate package names while preserving first-seen order
        if [[ " $updated_packages " != *" $package_name_tag "* ]]; then
            updated_packages="${updated_packages}${package_name_tag} "
        fi
		sleep 1
        if ! gh release view -R "github.com/$owner/$repo" "$package_name_tag" >/dev/null 2>&1; then
            if ! output=$(gh release create -R "github.com/$owner/$repo" "$package_name_tag" -n "$package_name_tag" 2>&1); then
                if echo "$output" | grep -Eqi 'already exists|tag .* already exists'; then
                    echo "release already exists: $package_name_tag"
                else
                    echo "$output" >&2
                    return 1
                fi
            fi
        fi
        # if ! gh release upload -R github.com/$owner/$repo $package_name_tag $deb_name --clobber; then
        #     echo "$deb_name issues while uploading"
        # fi
        upload_deb_to_dists_repo "$deb_name"
    done
    popd
}

## generate redundent debfile in release. files which has removed from dists but still present in gh release. 

list_redundent_deb() {
    redundent_deb_list=$(mktemp /tmp/red.XXXXXXXX)
    grep -vf $local_deb_list $remote_deb_list | uniq > $redundent_deb_list
}
#// better to execute it manually.  disable for now
remove_redundent_deb() {
    list_redundent_deb
    echo "removing redundent debs from remote"
    for deb in $(cat $redundent_deb_list);do
		sleep 1
        gh release delete-asset -R github.com/$owner/$repo $tag $deb -y
        echo "removed $deb"
    done
}

remove_archive_from_temp_gh() {
    echo "removing temporay archives"
    # remove only which has download. it wont take gurantee of succesfully processed. if some archives
    # not processed successfully. then most probably issues with archive itself. 
    # However repository consistency checker will catch any unsuccesful checks. 
    cd $BASE_DIR
    shopt -s nullglob
    for temp in ./*.tar;do
		sleep 1
        if gh release delete-asset -R github.com/$owner/tur 0.1 "$(basename $temp)" -y;then

            echo "$temp removed!!"
        else
            echo "Error while removing $temp"
        fi
    done
    shopt -u nullglob
}
## A rebuild always refreshes the "Date:" stamp and regenerates the
## signatures. When nothing else changed (no pool change, no Packages index
## change, Release differing from HEAD only in the Date line), restore the
## previously committed files so routine runs do not create pointless
## commits and signature rotations.
drop_date_only_changes() {
    pushd $(dirname $BASE_DIR)
    local status_output release_file
    # Everything except plain modifications of the signature trio counts as
    # a real change (pool edits, Packages index edits, added/removed files).
    status_output=$(git status --porcelain -- pool dists \
        | grep -Ev '^ M dists/[^/]+/(Release|InRelease|Release\.gpg)$' \
        || true)
    if [[ -n "$status_output" ]]; then
        echo "dists changed:"
        printf '%s\n' "$status_output"
        popd
        return
    fi
    for release_file in dists/*/Release; do
        [[ -f "$release_file" ]] || continue
        if ! diff <(git show "HEAD:$release_file" 2>/dev/null | grep -v '^Date: ') \
                  <(grep -v '^Date: ' "$release_file") >/dev/null; then
            echo "dists changed: $release_file"
            popd
            return
        fi
    done
    echo "dists unchanged, keeping previous Release and signatures"
    git checkout -- dists
    popd
}

build_version_changes() {
    declare -A old_ver new_ver
    local status file base pkg ver
    while IFS=$'\t' read -r status file; do
        [[ "$file" == pool/*/*.deb ]] || continue
        base=$(basename "$file")
        pkg="${base%%_*}"
        ver="${base#*_}"
        ver="${ver%%_*}"
        case "$status" in
            D) [[ -z "${old_ver[$pkg]:-}" ]] && old_ver["$pkg"]="$ver" ;;
            A) [[ -z "${new_ver[$pkg]:-}" ]] && new_ver["$pkg"]="$ver" ;;
        esac
    done < <(git diff --cached --no-renames --name-status -- pool/)

    local p
    for p in $(printf '%s\n' "${!new_ver[@]}" | sort); do
        if [[ -n "${old_ver[$p]:-}" ]]; then
            printf -- '- %s: %s -> %s\n' "$p" "${old_ver[$p]}" "${new_ver[$p]}"
        else
            printf -- '- %s: %s\n' "$p" "${new_ver[$p]}"
        fi
    done
}

commit() {
    drop_date_only_changes
    pushd $(dirname $BASE_DIR)
    echo "pushing changes"
    if [[ $(git status --porcelain) ]]; then
        git add .
        local commit_message="Update dists files"
        if [[ -n "${updated_packages:-}" ]]; then
            commit_message="Updated: ${updated_packages% }"
            local version_changes
            version_changes=$(build_version_changes)
            if [[ -n "$version_changes" ]]; then
                commit_message="${commit_message}

${version_changes}"
            fi
        fi
        git commit -m "$commit_message"
        git push
    else
        echo "nothing to commit"
    fi
    popd
    # Clean up processed tarballs even when there was nothing to commit,
    # otherwise they would be re-downloaded and re-processed forever.
    remove_archive_from_temp_gh
}
upload_debs
# remove_redundent_deb
commit
