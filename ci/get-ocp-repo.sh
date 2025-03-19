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
Usage: $0 <MODE> [OPTIONS]

  Fetch mirrored RHEL/OCP yum repo files from OpenShift CI's in-cluster service.
  The following modes are supported:

  --cosa-workdir PATH      Get RHEL and OCP versions from manifests in cosa workdir
  --ocp-layer    MANIFEST  Get RHEL version from /usr/lib/os-release and OCP version from manifest

  The following options are supported

  --output-dir   PATH      Directory to which to output ocp.repo file
EOF
    exit 1
}

info() {
    echo "INFO:" "$@" >&2
}

cleanup_repos() {
    # if we had installed the packages and created symlinks, remove it
    if rpm -q centos-release-cloud; then
        dnf remove -y centos-release-{cloud,nfv,virt}-common
        find "/usr/share/distribution-gpg-keys/centos" -type l -exec rm -f {} \;
        echo "Removed all symbolic links and packages installed for scos"
    fi
    # remove ocp.repo file
    if [ -n "$ocp_manifest" ]; then
        if [ -z "$output_dir" ]; then
            output_dir=$(dirname "$ocp_manifest")
        fi
    else
        if [ -z "$output_dir" ]; then
            output_dir="$cosa_workdir/src/config"
        fi
    fi
    rm "$output_dir/ocp.repo"
    echo "Removed repo file $output_dir/ocp.repo"
}

create_gpg_keys() {
    # Check if centos-stream-release is installed and centos-release-cloud is not
    # enablerepo added in case the repo is disabled (when building extensions)
    if rpm -q centos-stream-release && ! rpm -q centos-release-cloud; then
        dnf install -y centos-release-{cloud,nfv,virt}-common --enablerepo extras-common
    fi

    # Create directory for CentOS distribution GPG keys
    mkdir -p /usr/share/distribution-gpg-keys/centos
    # Create symbolic links for GPG keys
    if [ ! -e "/usr/share/distribution-gpg-keys/centos/RPM-GPG-KEY-CentOS-Official" ]; then
        ln -s /etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial /usr/share/distribution-gpg-keys/centos/RPM-GPG-KEY-CentOS-Official
        ln -s {/etc/pki/rpm-gpg,/usr/share/distribution-gpg-keys/centos}/RPM-GPG-KEY-CentOS-SIG-Cloud
        ln -s {/etc/pki/rpm-gpg,/usr/share/distribution-gpg-keys/centos}/RPM-GPG-KEY-CentOS-SIG-Extras-SHA512
        ln -s {/etc/pki/rpm-gpg,/usr/share/distribution-gpg-keys/centos}/RPM-GPG-KEY-CentOS-SIG-NFV
        ln -s {/etc/pki/rpm-gpg,/usr/share/distribution-gpg-keys/centos}/RPM-GPG-KEY-CentOS-SIG-Virtualization
    fi
}

cosa_workdir=
ocp_manifest=
output_dir=
rc=0
options=$(getopt --options h --longoptions help,cosa-workdir:,ocp-layer:,output-dir:,cleanup -- "$@") || rc=$?
[ $rc -eq 0 ] || print_usage_and_exit
eval set -- "$options"
while [ $# -ne 0 ]; do
    case "$1" in
        -h | --help) print_usage_and_exit;;
        --cosa-workdir) cosa_workdir=$2; shift;;
        --ocp-layer) ocp_manifest=$2; shift;;
        --output-dir) output_dir=$2; shift;;
        --cleanup) cleanup_repos; exit 0;;
        --) break;;
        *) echo "$0: invalid argument: $1" >&2; exit 1;;
    esac
    shift
done

if [ -n "$ocp_manifest" ]; then
    # --ocp-layer path
    ocp_version=$(rpm-ostree compose tree --print-only "$ocp_manifest" | jq -r '.metadata.ocp_version')
    ocp_version=${ocp_version//./-}
    info "Got OpenShift version $ocp_version from $ocp_manifest"
    # osname is used lower down, so set it
    osname=$(source /usr/lib/os-release; if [ $ID == centos ]; then echo scos; fi)

    if [ -z "$output_dir" ]; then
        output_dir=$(dirname "$ocp_manifest")
    fi

    # get rhel version corresponding to the release so we can get the
    # correct OpenShift rpms from those for scos. These packages are not
    # available in CentOS Stream
    if [ "$osname" = scos ]; then
        workdir=$(dirname "$ocp_manifest")
        manifest="$workdir/manifest.yaml"
        json=$(rpm-ostree compose tree --print-only "$manifest")
        version=$(jq -r '.["automatic-version-prefix"]' <<< "$json")
        rhel_version=$(cut -f2 -d. <<< "$version")
        info "Got RHEL version $rhel_version from rhel manifest for scos"
    else
        rhel_version=$(source /usr/lib/os-release; echo ${VERSION_ID//./})
        info "Got RHEL version $rhel_version from /usr/lib/os-release"
    fi
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

    if [ -z "$output_dir" ]; then
        output_dir="$cosa_workdir/src/config"
    fi
fi

mkdir -p "$output_dir"
repo_path="$output_dir/ocp.repo"

set -x
curl --fail -L "http://base-${ocp_version}-rhel${rhel_version}.ocp.svc.cluster.local" -o "$repo_path"
set +x

if [ "${rhel_version}" = 96 ]; then
    # XXX: also currently also add 9.4 repos for crun-wasm when building extensions
    # https://github.com/openshift/os/issues/1680
    # https://github.com/openshift/os/pull/1682
    # https://issues.redhat.com/browse/COS-3075
    curl --fail -L http://base-4-19-rhel94.ocp.svc.cluster.local >> "$repo_path"
fi

# If we're building the SCOS OKD variant, then strip away all the RHEL repos and just keep the plashet.
# Temporary workaround until we have all packages for SCOS in CentOS Stream.
if [ "$osname" = scos ]; then
    info "Neutering RHEL repos for SCOS"
    awk '/server-ose/,/^$/' "$repo_path" > "$repo_path.tmp"
    # only pull in certain Openshift packages as the rest come from the c9s repo
    sed -i '/^baseurl = /a includepkgs=openshift-* ose-aws-ecr-* ose-azure-acr-* ose-gcp-gcr-*' "$repo_path.tmp"
    # add the contents of the CentOS Stream repo
    workdir="$cosa_workdir/src/config"
    if [ -n "$ocp_manifest" ]; then
        workdir=$(dirname "$ocp_manifest")
    fi
    # pull in the mirror repo as well in case there are newer versions in the composes
    # and we require older versions - this happens because we build the node images async
    # and the composes move fast.
    cat "$workdir/c9s.repo" >> "$repo_path.tmp"
    cat "$workdir/c9s-mirror.repo" >> "$repo_path.tmp"
    mv "$repo_path.tmp" "$repo_path"
    create_gpg_keys
fi

cat "$repo_path"
