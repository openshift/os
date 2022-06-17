#!/bin/bash
# Select the version of RHCOS or SCOS that you want to build from this repo
set -euxo pipefail

# The current default for RHCOS in OCP 4.11 and later is RHEL 8.6
RHELVER="rhel-8.6"

main() {
    local osver=""
    local content_sets_required="false"
    if [[ "$#" -ne 1 ]]; then
        osver="$RHELVER"
    else
        osver="$1"
    fi

    case "$osver" in
        "rhel-8.6" | "rhel-9.0")
            echo "Building RHCOS based on ${osver}"
            content_sets_required="true"
            ;;
        *)
            echo "Unknown OS version: ${osver}"
            exit 1
            ;;
    esac

    ln -snf "extensions-${osver}.yaml" "extensions.yaml"
    ln -snf "${osver}.yaml" "manifest.yaml"
    if [[ "${content_sets_required}" == "true" ]]; then
        ln -snf "content_sets-${osver}.yaml" "content_sets.yaml"
    fi
}

main "${@}"
