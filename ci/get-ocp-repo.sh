#!/bin/bash
set -euo pipefail

# This script is used when running within the OpenShift CI clusters to fetch
# the RHEL and OCP yum repo files from an in-cluster service that mirrors the
# content. It's called from three places:
# - prow-entrypoint.sh: CI tests that build & and test different variants
# - extensions/Dockerfile: when building the extensions container in OpenShift CI
# - Containerfile: when building the node image in CI

print_usage_and_exit() {
    cat 1>&2 <<'EOF'
Usage: $0 <MODE>

  Fetch mirrored RHEL/OCP yum repo files from OpenShift CI's in-cluster service.
  The following modes are supported:

  --cosa-workdir PATH      Get RHEL and OCP versions from manifests in cosa workdir
  --ocp-layer    MANIFEST  Get RHEL version from /usr/lib/os-release and OCP version from manifest
EOF
    exit 1
}

info() {
    echo "INFO:" "$@" >&2
}

if [ $# -eq 0 ]; then
    print_usage_and_exit
else
    mode=$1; shift
    cosa_workdir=
    ocp_manifest=
    if [ "$mode" = "--cosa-workdir" ]; then
        cosa_workdir=$1; shift
    elif [ "$mode" = "--ocp-layer" ]; then
        ocp_manifest=$1; shift
    else
        print_usage_and_exit
    fi
fi

if [ -n "$ocp_manifest" ]; then
    # --ocp-layer path
    rhel_version=$(source /usr/lib/os-release; echo ${VERSION_ID//./})
    info "Got RHEL version $rhel_version from /usr/lib/os-release"
    ocp_version=$(rpm-ostree compose tree --print-only "$ocp_manifest" | jq -r '.metadata.ocp_version')
    ocp_version=${ocp_version//./-}
    info "Got OpenShift version $ocp_version from $ocp_manifest"
    # osname is used lower down, so set it
    osname=$(source /usr/lib/os-release; if [ $ID == centos ]; then echo scos; fi)
else
    [ -n "$cosa_workdir" ]
    # --cosa-workdir path

    # the OCP version always comes from packages-openshift.yaml
    ocp_version=$(rpm-ostree compose tree --print-only "$cosa_workdir/src/config/packages-openshift.yaml" | jq -r '.metadata.ocp_version')
    ocp_version=${ocp_version//./-}
    info "Got OpenShift version $ocp_version from packages-openshift.yaml"

    # the RHEL version comes from the target manifest

    # first, make sure we're looking at the right manifest
    manifest="$cosa_workdir/src/config/manifest.yaml"
    if [ -f "$cosa_workdir/src/config.json" ]; then
        variant="$(jq --raw-output '."coreos-assembler.config-variant"' 'src/config.json')"
        manifest="$cosa_workdir/src/config/manifest-${variant}.yaml"
    fi

    # flatten manifest and query a couple of fields
    json=$(rpm-ostree compose tree --print-only "$manifest")
    osname=$(jq -r '.metadata.name' <<< "$json")
    is_ocp_variant=$(jq '.packages | contains(["cri-o"])' <<< "$json")

    if [ "$osname" = scos ] && [ "$is_ocp_variant" = false ]; then
        # this is the pure SCOS case; we don't need any additional repos at all
        info "Building pure SCOS variant. Exiting..."
        exit 0
    elif [ "$osname" = scos ]; then
        # We still need the OCP repos for now unfortunately because not
        # everything is in the Stream repo. For the RHEL version, just use the
        # default variant's one.
        json=$(rpm-ostree compose tree --print-only "$cosa_workdir/src/config/manifest.yaml")
    fi
    version=$(jq -r '.["automatic-version-prefix"]' <<< "$json")
    if [ "$is_ocp_variant" = true ]; then
        # RHEL version is second field
        info "Building OCP variant"
        rhel_version=$(cut -f2 -d. <<< "$version")
    else
        # RHEL version is first and second field
        info "Building pure variant"
        rhel_version=$(cut -f1-2 -d. <<< "$version")
        rhel_version=${rhel_version//./}
    fi
    info "Got RHEL version $rhel_version from automatic-version-prefix value $version"
fi

repo_path="$cosa_workdir/src/config/ocp.repo"

set -x
curl --fail -L "http://base-${ocp_version}-rhel${rhel_version}.ocp.svc.cluster.local" -o "$repo_path"
set +x

# If we're building the SCOS OKD variant, then strip away all the RHEL repos and just keep the plashet.
# Temporary workaround until we have all packages for SCOS in CentOS Stream.
if [ "$osname" = scos ]; then
    info "Neutering RHEL repos for SCOS"
    awk '/server-ose/,/^$/' "$repo_path" > "$repo_path.tmp"
    mv "$repo_path.tmp" "$repo_path"
fi

cat "$repo_path"
