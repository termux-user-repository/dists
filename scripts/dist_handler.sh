#!/usr/bin/env bash
set -e -o pipefail
shopt -s extglob
BASE_DIR=$(realpath "$(dirname "$BASH_SOURCE")")
POOL_DIR="$(dirname "$BASE_DIR")/pool"
PROCESSED_DEB=$BASE_DIR/processed_deb
mkdir -p $PROCESSED_DEB
echo $POOL_DIR
Dists_DIR="$(dirname "$BASE_DIR")/dists"
REPO_JSON="$(dirname "$BASE_DIR")/repo.json"
arch_array=("aarch64" "arm" "i686" "x86_64")
components_array=($(jq -r .[].name  $REPO_JSON | tr '\n' ' '))
# Info being added into release file
ORIGIN="Termux-user-repository"
Suite="tur-packages"
Codename="tur-packages"
Architectures="aarch64 arm i686 x86_64"
Components=$(for i in "${components_array[@]}";do echo -n "$i ";done)
Description="Created with love for Termux community"

download_unprocessed_debs() {
    pushd $BASE_DIR
    rm -rf ./*.tar
    gh release download -R termux-user-repository/tur 0.1 -p "*.tar"
    popd
    
}
create_dist_structure() {
    echo "Creating dist structure"
    # remove all files and dir in dists.
    rm -rf $Dists_DIR
    mkdir -p $Dists_DIR
    mkdir -p $POOL_DIR
    mkdir -p $Dists_DIR/$Suite
    ## component dir.
    for comp in "${components_array[@]}";do
        mkdir -p $Dists_DIR/$Suite/$comp 
        mkdir -p $Dists_DIR/$Suite/$comp/binary-{aarch64,arm,i686,x86_64}
        ## pool direcectory if not exist.
        mkdir -p $POOL_DIR/$comp
    done



}
# add packages in pool. Not package actually, it just write packages metadata in pool.
add_package_metadata() {
    echo "Package metadata"
    cd $BASE_DIR
    rm -rf debs
    ## EXTRACT TAR FROM ZIP IF ANY
    count_zip_file=$(find . -maxdepth 1 -name "*.zip" 2> /dev/null | wc -l)
    if [ $count_zip_file != 0 ];then
        for zipped in ./*.zip;do
        unzip -o $zipped
        done
    fi
    for tar_file in ./*.tar;
    do
        echo "processing $tar_file"
        tar -xf $tar_file
        
        if test -f debs/built*.txt;then
            repo_component=$(ls debs/built*.txt | cut -d_ -f2)
        else
            continue
        fi
        
        # Allow nullglob patterns.
        shopt -s nullglob
        for deb_file in debs/*.deb;do
            deb_file=$(basename $deb_file)
            echo "scanning $deb_file"
            dpkg-scanpackages debs/$deb_file >| $POOL_DIR/$repo_component/$deb_file 
            ## update Filename: indices to relative path
            sed -i "/Filename:/c\Filename: pool/$repo_component/$deb_file" $POOL_DIR/$repo_component/$deb_file
        done
        shopt -u nullglob
        mv -f debs/* $PROCESSED_DEB
    done
}
remove_old_version() {
	echo "Removing Old version debfiles....."
	for comp in "${components_array[@]}";do
		cd $POOL_DIR/$comp 
		for package_name in `ls | cut -d'_' -f1 | uniq`; do
			_versions="$(find . -name "${package_name}_*_*.deb" | sed -E 's|^.*/([^_]*)_([^_]*)_([^\.]*)\.deb$|\2|g')"
			latest_version="$(echo "$_versions" | tail -n1)"
			for _version in $_versions; do
				if dpkg --compare-versions "$_version" gt "$latest_version"; then
					latest_version="$_version"
				fi
			done
			echo "Latest $package_name $latest_version"
			find . -name "${package_name}_*" -not -iname "${package_name}_${latest_version}_*" -exec rm {} \;
		done
	done

}

create_packages() {
    echo "creating package file. "
    for comp in "${components_array[@]}";do
        echo "creating packages for $comp components"
        cd $POOL_DIR/$comp
        for arch in "${arch_array[@]}";do
            echo $arch
            echo $(pwd)
            count_deb_metadata_file=$(find . -name "*[$arch|all].deb" 2> /dev/null | wc -l)
            echo "$count_deb_metadata_file"
            if [[ $count_deb_metadata_file == 0 ]];then
                echo "continue"
                continue
            fi
            echo "$(pwd) $comp"
            cat ./*{$arch,all}.deb 2>/dev/null >| $Dists_DIR/$Suite/$comp/binary-${arch}/Packages || true

            gzip -9k $Dists_DIR/$Suite/$comp/binary-${arch}/Packages
            echo "packages file created for $comp $arch"
        done
    done
}

add_general_info() {
    release_file_path=$1
    date_=$(date -uR)
    Arch=$2
    if [ $Arch == "all" ];then
        Arch=$Architectures
    fi
    cat > $release_file_path <<-EOF
Origin: $ORIGIN $Codename
Label: $ORIGIN $Codename
Suite: $Suite
Codename: $Codename
Date: $date_
Architectures: $Arch
Components: $Components
Description: $Description
EOF
}

generate_release_file() {
    r_file=$Dists_DIR/$Suite/Release
    rm -f $r_file
    touch $r_file
    cd $Dists_DIR/$Suite

    # add general info in main release file
    add_general_info $r_file "all"
    sums_array=("MD5" "SHA1" "SHA256" "SHA512")
    
    for sum in "${sums_array[@]}";do
        case $sum in
            MD5) 
                checksum=md5sum
                ;;
            SHA1)
                checksum=sha1sum
                ;;
            SHA256)
                checksum=sha256sum
                ;;
            SHA512)
                checksum=sha512sum
                ;;
            *)
                echo '...'
                exit 1
        esac
        echo "processing $sum"
        echo "${sum}:" >> $r_file
        for file in $(find $Components -type f);do
            generated_sum=$($checksum $file | cut -d' ' -f1 )
            filename_and_size=$(wc -c $file)
            echo " $generated_sum $filename_and_size" >> $r_file
            done
    done
            

}
sign_release_file() {
    cd $Dists_DIR/$Suite
    if [[ -n "$SEC_KEY" ]]; then
        echo "Importing key"
        if echo -n "$SEC_KEY" | base32 --decode | gpg --import --batch --yes;then
              echo "*********key imported successfully********"
        else
            echo "Issues while importing private key"
            exit 1
        fi

    fi
    echo "Signing Release file"
    gpg --passphrase "$(echo -n $SEC_PASS | base32 --decode)" --batch --yes --pinentry-mode loopback -u 43EEC3A2934343315717FF6F6A5C550C260667D1 -bao ./Release.gpg Release
    gpg --passphrase "$(echo -n $SEC_PASS | base32 --decode)" --batch --yes --pinentry-mode loopback -u 43EEC3A2934343315717FF6F6A5C550C260667D1 --clear-sign --output InRelease Release
}
download_unprocessed_debs
create_dist_structure
add_package_metadata
remove_old_version
create_packages
generate_release_file
sign_release_file
