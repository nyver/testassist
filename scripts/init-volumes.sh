#!/bin/sh
# Creates the bind-mount directories used by docker/compose.yaml and makes them
# writable by the container's non-root user (UID/GID 65532).
#
# Usage: scripts/init-volumes.sh [target-dir]   (default: docker/ next to this script)
set -eu

UID_GID="65532:65532"
root=$(cd "$(dirname "$0")/.." && pwd)
target=${1:-$root/docker}

mkdir -p "$target/data" "$target/certs"

if [ "$(id -u)" -eq 0 ]; then
    chown -R "$UID_GID" "$target/data" "$target/certs"
else
    echo "Changing ownership to $UID_GID needs root; running sudo."
    sudo chown -R "$UID_GID" "$target/data" "$target/certs"
fi
chmod 750 "$target/data" "$target/certs"

echo "Ready: $target/data and $target/certs are owned by $UID_GID."
