#!/bin/sh
recover_metadata_preparations() {
    meta_base=$1
    meta_prefix=$2
    meta_identity_name=$3
    meta_identity_source=$4
    meta_marker=$5
    for meta_dir in "$meta_base/$meta_prefix"*; do
        [ -e "$meta_dir" ] || [ -L "$meta_dir" ] || continue
        meta_suffix=${meta_dir#"$meta_base/$meta_prefix"}
        [ "${#meta_suffix}" -eq 10 ] || fail "Unknown metadata preparation name; preserving data"
        case "$meta_suffix" in *[!A-Za-z0-9]*) fail "Unknown metadata preparation name; preserving data";; esac
        [ ! -L "$meta_dir" ] && [ -d "$meta_dir" ] && [ "$(stat -c '%u:%a' "$meta_dir")" = 0:700 ] || fail "Unknown metadata preparation directory; preserving data"
        for meta_entry in "$meta_dir"/* "$meta_dir"/.[!.]* "$meta_dir"/..?*; do
            [ -e "$meta_entry" ] || [ -L "$meta_entry" ] || continue
            [ ! -L "$meta_entry" ] && [ -f "$meta_entry" ] && [ "$(stat -c '%u:%a' "$meta_entry")" = 0:600 ] || fail "Unknown metadata preparation entry; preserving data"
            meta_size=$(wc -c < "$meta_entry")
            case "${meta_entry##*/}" in
                "$meta_identity_name")
                    head -c "$meta_size" "$meta_identity_source" | cmp -s - "$meta_entry" || fail "Metadata preparation identity mismatch; preserving data"
                    ;;
                .inception-owned)
                    printf '%s\n' "$meta_marker" | head -c "$meta_size" | cmp -s - "$meta_entry" || fail "Metadata preparation marker mismatch; preserving data"
                    ;;
                *) fail "Unknown metadata preparation contents; preserving data";;
            esac
        done
        rm -rf -- "$meta_dir"
    done
}

publish_metadata() {
    meta_base=$1
    meta_prefix=$2
    meta_identity_name=$3
    meta_identity_source=$4
    meta_marker=$5
    meta_destination=$6
    [ ! -e "$meta_destination" ] && [ ! -L "$meta_destination" ] || fail "Metadata destination already exists; preserving data"
    meta_dir=$(mktemp -d "$meta_base/${meta_prefix}XXXXXXXXXX")
    printf '%s\n' "$meta_marker" > "$meta_dir/.inception-owned"
    cp "$meta_identity_source" "$meta_dir/$meta_identity_name"
    mv -T -- "$meta_dir" "$meta_destination"
}
