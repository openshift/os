#!/bin/bash
dn="$(dirname $0)"
exec "${dn}/prow-entrypoint.sh" "validate"
