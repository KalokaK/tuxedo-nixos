#!/usr/bin/env nix-shell
#! nix-shell -i bash -p nix curl

# Compute the source hash and npm dependency hash needed to bump
# tuxedo-control-center to a new version in default.nix.
#
# Usage: ./update.sh <tcc-version>
# Example: ./update.sh 3.0.6
#
# The values printed below go into default.nix:
#   - src.hash      -> the fetchFromGitHub hash
#   - npmDepsHash   -> the buildNpmPackage dependency hash

set -eu -o pipefail

if [ "$#" -ne 1 ]; then
    >&2 echo "Error: Missing version parameter"
    >&2 echo
    >&2 echo "Usage: $0 tcc-version"
    >&2 echo
    >&2 echo "Example:"
    >&2 echo "$0 3.0.6"

    exit 1
fi

TUXEDO_VERSION="$1"

echo "Fetching source for v${TUXEDO_VERSION} ..."
SRC_HASH=$(nix-prefetch-url --unpack --type sha256 \
    "https://github.com/tuxedocomputers/tuxedo-control-center/archive/refs/tags/v${TUXEDO_VERSION}.tar.gz" \
    | tail -1 | xargs nix hash to-sri --type sha256)

echo "Fetching package-lock.json and computing npmDepsHash ..."
WORKDIR=$(mktemp -d)
trap 'rm -r "$WORKDIR"' EXIT
curl -f "https://raw.githubusercontent.com/tuxedocomputers/tuxedo-control-center/v${TUXEDO_VERSION}/package-lock.json" \
    > "$WORKDIR/package-lock.json"
NPM_DEPS_HASH=$(nix run nixpkgs#prefetch-npm-deps -- "$WORKDIR/package-lock.json")

echo
echo "Update the following values in default.nix:"
echo
echo "  version     = \"${TUXEDO_VERSION}\";"
echo "  src.hash    = \"${SRC_HASH}\";"
echo "  npmDepsHash = \"${NPM_DEPS_HASH}\";"
