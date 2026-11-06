#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STAGING_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/easyhidpi-dev.XXXXXX")
trap 'rm -rf "$STAGING_ROOT"' EXIT
STAGED_APP="$STAGING_ROOT/$APP_NAME.app"

stage_app debug "$STAGED_APP"

unlock_signing_keychain
SIGNING_IDENTITY=-
if has_signing_identity; then
    SIGNING_IDENTITY=$CODESIGN_IDENTITY
fi
codesign --force --sign "$SIGNING_IDENTITY" "$STAGED_APP"

install_app "$STAGED_APP"
