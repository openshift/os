#!/usr/bin/env python3

"""
This script builds RHCOS extensions by downloading RPM packages specified in a YAML configuration file.

The script:
1. Reads an extensions YAML file that defines extension packages
2. Filters extensions by architecture if specified
3. Downloads each extension's packages and dependencies using dnf
4. Places all RPMs in /usr/share/rpm-ostree/extensions/

Example usage:
    python3 build_extensions.py extensions/rhel-10.2.yaml
"""

import yaml
import subprocess
import sys
import os


def main() -> None:
    """
    Main entry point for building extensions from a YAML configuration file.
    """
    if len(sys.argv) < 2:
        print("Usage: build_extensions.py <extensions_yaml>", file=sys.stderr)
        sys.exit(1)

    extensions_yaml = sys.argv[1]

    print(f"Loading extensions from {extensions_yaml}")
    with open(extensions_yaml) as f:
        config = yaml.safe_load(f)

    extensions = config.get("extensions", {})
    print(f"Found {len(extensions)} extensions")

    for ext_name, ext_config in extensions.items():
        if not isinstance(ext_config, dict):
            continue

        packages = ext_config.get("packages", [])
        if not packages:
            continue

        # Check architecture filter if specified
        if "architectures" in ext_config:
            archs = ext_config["architectures"]
            current_arch = os.uname().machine
            if current_arch not in archs:
                print(f"Skipping {ext_name}: architecture {current_arch} not in {archs}")
                continue

        print(f"Downloading extension: {ext_name}")
        print(f"  Packages: {', '.join(packages)}")
        sys.stdout.flush()

        # Use dnf download to get RPMs with all dependencies
        # Disable subscription-manager plugin to avoid hangs
        cmd = ["dnf", "download", "--disableplugin=subscription-manager", "--resolve", "--alldeps", "--destdir=/usr/share/rpm-ostree/extensions/"] + packages
        print(f"  Running: {' '.join(cmd)}")
        sys.stdout.flush()

        # Don't capture output so we can see dnf progress
        result = subprocess.run(cmd)
        if result.returncode != 0:
            print(f"Error downloading {ext_name}", file=sys.stderr)
            sys.exit(1)

        print(f"  Downloaded successfully")

    print("All extensions downloaded to /usr/share/rpm-ostree/extensions/")


if __name__ == "__main__":
    main()
