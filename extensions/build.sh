#!/bin/bash
set -xeuo pipefail

# fetch repos from in-cluster mirrors if we're running in OpenShift CI
if [ "${OPENSHIFT_CI}" != 0 ]; then
    ci/get-ocp-repo.sh ocp.repo
fi

# add all the repos from the src dir (including mounted secret.repo)
# into /etc/yum.repos.d so dnf sees them
cat /os/*.repo >> /etc/yum.repos.d/git.repo

. /etc/os-release
arch=$(uname -m)
destdir=/usr/share/rpm-ostree/extensions/
mkdir -p "${destdir}"

# Determine which extensions YAML file to use based on OS
extensions_yaml="extensions/${ID}-${VERSION_ID}.yaml"

# Check if the extensions YAML file exists
if [ ! -f "$extensions_yaml" ]; then
    echo "Error: Extensions file not found: $extensions_yaml"
    exit 1
fi

# Convert YAML to JSON using Python (yq is not available in base image)
# We preserve comments in YAML but convert to JSON for jq processing
extensions_json=$(mktemp)
python3 -c 'import sys, yaml, json; y=yaml.safe_load(sys.stdin.read()); print(json.dumps(y))' < "$extensions_yaml" > "$extensions_json"

# Version lock to the specific packages installed on the system already
dnf --disablerepo=* versionlock add '*'

# Also versionlock kernel-{devel,headers} and *any* potential kernel package that gets
# installed (kernel-rt, kernel-64k, etc) to the same EVR as the kernel that's already
# installed in the system.
kernel_evr=$(rpm -q kernel-core --queryformat \
             "%|%EPOCH?{%{EPOCH}}:{0}|:%{VERSION}-%{RELEASE}")
for kernel_variant in 'rt' '64k'; do
    echo "kernel-${kernel_variant}-core-${kernel_evr}.*" >> /etc/dnf/plugins/versionlock.list
    echo "kernel-${kernel_variant}-devel-${kernel_evr}.*" >> /etc/dnf/plugins/versionlock.list
done
echo "kernel-headers-${kernel_evr}.*" >> /etc/dnf/plugins/versionlock.list
echo "kernel-devel-${kernel_evr}.*" >> /etc/dnf/plugins/versionlock.list

# Collect all packages and additional repos from all applicable extensions
all_packages=()

# Loop through all extensions defined in the JSON file
for extension in $(jq -r '.extensions | keys[]' "$extensions_json"); do
    echo "Processing extension: ${extension}"

    # Check architecture constraints
    architectures=$(jq -r ".extensions[\"${extension}\"].architectures[]? // empty" "$extensions_json")
    if [ -n "$architectures" ]; then
        # Extension has architecture constraints - check if current arch matches
        arch_match=false
        for ext_arch in $architectures; do
            if [ "$arch" = "$ext_arch" ]; then
                arch_match=true
                break
            fi
        done
        if [ "$arch_match" = false ]; then
            echo "Skipping ${extension} (not for ${arch})"
            continue
        fi
    fi

    # Get packages for this extension from JSON
    packages=$(jq -r ".extensions[\"${extension}\"].packages[]" "$extensions_json")

    # Error if no packages defined for this extension
    if [ -z "$packages" ]; then
        echo "Error: No packages defined for extension: ${extension}"
        exit 1
    fi

    # Add packages to the collection
    echo "  Including packages: ${packages}"
    all_packages+=($packages)
done

# Error if no packages to download at all
if [ ${#all_packages[@]} -eq 0 ]; then
    echo "Error: No packages to download for any extension"
    exit 1
fi

# Combine global repos with any extension-specific repos
repo_list="${YUM_REPO_NAMES},${EXTENSIONS_YUM_REPO_NAMES}"

# Download all packages.
echo "Downloading all extension packages (${#all_packages[@]} packages)..."
# `dnf download` for dnf4 doesn't seem to respect versionlock so we'll
# use `dnf install` with the `--downloadonly` flag here. `dnf install`
# won't re-download packages that are already installed in the system
# so we have to add a second `dnf reinstall` to get the kernel
# package RPM files that we also want in our extensions.
#
# So `dnf download` becomes `dnf install && dnf reinstall`. The
# install downloads packages that aren't already installed and the
# reinstall downloads packages that are already installed. This is
# likely not a limitiation of dnf5 `dnf download`.
#
# Leverage --nobest so older versions of packages can be used when
# versionlocking would require that.
#
# Leverage skip_if_unavailable=True for cases where repos exist for
# only specific architectures.
for subcommand in 'install' 'reinstall'; do
    dnf --repo="${repo_list}" "${subcommand}" \
        --assumeyes                           \
        --nobest                              \
        --downloadonly                        \
        --setopt=skip_if_unavailable=True     \
        --destdir="${destdir}"                \
        "${all_packages[@]}"
done

# Clear the versionlock and clean up dnf caches / yum repo files we created
dnf --disablerepo=* versionlock clear
dnf clean all
rm -vf /etc/yum.repos.d/{ocp,git,redhat}.repo

# Clean up temporary JSON file
rm -f "$extensions_json"
