#!/bin/bash
set -xeuo pipefail

# This script assumes that `cosa init` has been run.
cosa build
cosa buildextend-extensions
