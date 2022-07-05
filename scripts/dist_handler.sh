#!/usr/bin/env bash
set -e -o pipefail

BASE_DIR=$(realpath "$(dirname "$BASH_SOURCE")")
POOL_DIR="$(dirname "$BASE_DIR")/pool"
echo $POOL_DIR
Dists_DIR="$(dirname "$BASE_DIR")/dists"

arch_array=("aarch64" "arm" "i686" "x86_64")

# Info being add into release file
ORIGIN="Termux-user-repository"
Suite="stable"
Codename="stable"
Architectures="aarch64 arm i686 x86_64"
Components="tur"
Description="Created with love for termux community"

download_unprocessed_debs() {
    pushd $BASE_DIR
    rm -rf *.tar
    gh release download -R termux-user-repository/tur 0.1 -p "*.tar"
    for i in ./*.tar;do
        echo 'lol'
        echo $i
        tar -xvf $i 
    done
    popd
    
}
create_dist_structure() {
    # remove all files and dir in dists.
    rm -rf $Dists_DIR
    mkdir -p $Dists_DIR
    mkdir -p $Dists_DIR/$Suite
    mkdir -p $Dists_DIR/$Suite/$Components
    mkdir -p $Dists_DIR/$Suite/$Components/binary-{aarch64,arm,i686,x86_64}
}
# add packages in pool. Not package actually, it just write packages metadata in pool.
add_package_metadata() {
    cd $BASE_DIR
    for file in debs/*.deb;
    do
        file=$(basename $file)
        echo "scanning $file"
        dpkg-scanpackages debs/$file >| $POOL_DIR/$file 

        ## update Filename: indices to relative path
        sed -i "/Filename:/c\Filename: pool/$file" $POOL_DIR/$file
    done
}
remove_old_version() {
    pushd $POOL_DIR
    for dup_pkg in $(find . -type f | cut -d_ -f1,2 | uniq | cut -d_ -f1 | uniq -d);do
        old_version=$(find . -maxdepth 1 -type f -wholename "$dup_pkg*" | cut -d_ -f1,2 | uniq | sort | head -n-1)
        for older_deb in $old_version;do
            rm -f $older_deb*
            echo "Removed $older_deb"
        done
    done
    popd
}
create_packages() {
    echo " creating package file. "
    for arch in "${arch_array[@]}";do
        cat $POOL_DIR/*${arch}.deb >| $Dists_DIR/$Codename/$Components/binary-${arch}/Packages
        gzip -9k $Dists_DIR/$Codename/$Components/binary-${arch}/Packages
        echo "packages file created for $arch"
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
    # rm $r_file
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
        echo -n "$SEC_KEY" | base64 --decode | gpg --import
    fi
    echo "Signing Release file"
    gpg --passphrase $KCUBE_PASS --batch --yes --pinentry-mode loopback -u D613AC03FA1859E0337541B96F7DD85B65C5A5DE -bao ./Release.gpg Release
    gpg --passphrase $KCUBE_PASS --batch --yes --pinentry-mode loopback -u D613AC03FA1859E0337541B96F7DD85B65C5A5DE --clear-sign --output InRelease Release
}
download_unprocessed_debs
create_dist_structure
add_package_metadata
remove_old_version
create_packages
generate_release_file
sign_release_file
