#!/usr/bin/env bash

# Get all releases
release_list=$(mktemp /tmp/release.XXXXXXXXX.list)
gh release view --json 'assets' -q '.assets[] | .name' | sort | uniq > $release_list

keep_list=$(mktemp /tmp/keep.XXXXXXXXX.list)
# Keep all versions of ndk-sysroot
cat $release_list | grep "ndk-sysroot" > $keep_list
for _deb_file in pool/*/*.deb; do
    _deb_name="$(basename $_deb_file)"
    _deb_file_after_sed="$(echo "$_deb_name" | sed 's/[^a-zA-Z0-9._+-]/./g')"
    echo "$_deb_file_after_sed" >> $keep_list
done
cat $keep_list | sort | uniq > $keep_list.tmp
mv $keep_list.tmp $keep_list

delete_list=$(mktemp /tmp/release.XXXXXXXXX.list)
python -c "
with open('$release_list', 'r') as fp:
  release_lines = fp.readlines()
release_lines = list(map(str.strip, release_lines))
# print(release_lines)
release_lines = set(release_lines)

with open('$keep_list', 'r') as fp:
  keep_lines = fp.readlines()
keep_lines = list(map(str.strip, keep_lines))
# print(keep_lines)
keep_lines = set(keep_lines)

diff_in_keep_but_not_release = keep_lines - (keep_lines & release_lines)
assert len(diff_in_keep_but_not_release) == 0, str(diff_in_keep_but_not_release)

delete_list = release_lines - keep_lines
print('\n'.join(sorted(delete_list)))
" > $delete_list

for deb in $(cat $delete_list); do
    echo "$deb is ready to be deleted"
    gh release delete-asset 0.1 $deb -y
    echo "$deb deleted"
    sleep 1s
done
