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

wait_for_repo_ready() {
    local full_repo="$1"
    local attempt

    for attempt in $(seq 1 30); do
        if gh repo view "$full_repo" >/dev/null 2>&1; then
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

    pushd $DEB_DIR
    for deb in *.deb; do
        modified_name="$(echo "$deb" | sed 's/[^\a-zA-Z0-9._+-]/./g')"
        mv -n "$deb" "$modified_name"
        echo "$modified_name" >> $non_uploaded_list
    done
    for deb_name in $(cat $non_uploaded_list); do
        local package_name_tag=$(echo $deb_name | cut -d '_' -f 1)
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
    for temp in ./*.tar;do
		sleep 1
        if gh release delete-asset -R github.com/$owner/tur 0.1 "$(basename $temp)" -y;then

            echo "$temp removed!!"
        else
            echo "Error while removing $temp"
        fi
    done
}
commit() {
    pushd $(dirname $BASE_DIR)
    echo "pushing changes"
    if [[ $(git status --porcelain) ]]; then
        git add .
        git commit -m "Updated $list_updated_packages"
        git push
        remove_archive_from_temp_gh
    fi
}
upload_debs
# remove_redundent_deb
commit
