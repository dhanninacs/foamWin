#!/bin/bash
set -euo pipefail
exec "$(dirname "$0")/../OpenFOAM-14/build-all.sh" "$@"
