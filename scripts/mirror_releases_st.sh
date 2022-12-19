#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

JQ_FILTER=\
'map({
    "key": .tag_name, 
    "value": .assets 
        | map( select( (.name | endswith("sha256") | not) ) )
        | map({ key: .name | ltrimstr("container-structure-test-"), value: "sha256-" })
        | from_entries 
}) | from_entries
'

INFO="$(curl --silent -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/GoogleContainerTools/container-structure-test/releases?per_page=1 | jq "$JQ_FILTER")"

# TODO: remove this for loop once https://github.com/project-zot/zot/issues/715 is fixed.
for VERSION in $(jq -r 'keys | join("\n")' <<< $INFO); do 
    for PLATFORM in $(jq -r ".[\"$VERSION\"] | keys | join(\"\n\")" <<< $INFO); do 
        SHA256=$(curl -fLs "https://github.com/GoogleContainerTools/container-structure-test/releases/download/$VERSION/container-structure-test-$PLATFORM" | sha256sum | xxd -r -p | base64)
        INFO=$(jq ".[\"$VERSION\"][\"$PLATFORM\"] = \"sha256-$SHA256\"" <<< $INFO)
    done
done

echo -n "ST_VERSIONS = "
echo $INFO | jq -M

echo ""
echo "Copy the version info into oci/private/versions.bzl"