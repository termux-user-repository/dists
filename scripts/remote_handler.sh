#!/usr/bin/env bash

BASE_DIR=$(realpath "$(dirname "$BASH_SOURCE")")
DEB_DIR=$BASE_DIR/debs
POOL_DIR="$(dirname "$BASE_DIR")/pool"
owner="termux-user-repository"
repo="dists"
tag="0.1"
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

    find . -type f -exec basename '{}' \; | sed 's/[^\/\.a-Z0-9\+\_\-]/\./g' > $local_deb_list
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
    list_non_upload_debs
    pushd $DEB_DIR
    for deb in *.deb;do
        modified_name=$(echo $deb | sed 's/[^\/\.a-Z0-9\+\_\-]/\./')
        mv $deb $modified_name
    done
    for deb_name in $(cat $non_uploaded_list); do 
        gh release upload -R github.com/$owner/$repo $tag $deb_name
        echo "$deb_name uploaded!"
    done
    popd
}

## generate redundent debfile in release. files which has removed from dists but still present in gh release. 

list_redundent_deb() {
    redundent_deb_list=$(mktemp /tmp/red.XXXXXXXX)
    grep -vf $local_deb_list $remote_deb_list | uniq > $redundent_deb_list
}

remove_redundent_deb() {
    list_redundent_deb
    echo "removing redundent debs from remote"
    for deb in $(cat $redundent_deb_list);do
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
        if gh release delete-asset -R github.com/$owner/tur $tag "$(basename $temp)" -y;then

            echo "$temp removed!!"
        else
            echo "Error while removing $temp"
        fi
    done
}
commit() {
    pushd $(dirname $BASE_DIR)
    echo "pushing changes"
    last_commit=$(git log --oneline | head -n1 | cut -d' ' -f1)
    list_updated_packages=$(git diff ${last_commit} ./*/*/*/*/*/Packages| cat | grep +Package | sort -u | cut -d' ' -f2)
    if [[ $(git status --porcelain) ]]; then
        git add .
        git commit -m "Updated $list_updated_packages"
        if git push;then
            remove_archive_from_temp_gh
        fi
    fi
}
upload_debs
remove_redundent_deb
commit