#!/usr/bin/env bash
# Validates that Release.xcconfig has real values before archiving.
# Run in CI pre-archive step: bash scripts/validate_release_config.sh
set -euo pipefail

XCCONFIG="NeuroFlow/Config/Release.xcconfig"

error() { echo "❌ $1" >&2; exit 1; }

CERT_HASH=$(grep "NeuroFlowPinnedCertHashes" "$XCCONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')
API_URL=$(grep "NeuroFlowAPIBaseURL" "$XCCONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')

[[ "$API_URL" == *"your-domain"* ]] && error "Release.xcconfig: NeuroFlowAPIBaseURL still has placeholder value."
[[ "$CERT_HASH" == *"REPLACE_WITH"* ]] && error "Release.xcconfig: NeuroFlowPinnedCertHashes is still a placeholder. Run the openssl command in the file header to get the real hash."
[[ ${#CERT_HASH} -lt 64 ]] && error "Release.xcconfig: NeuroFlowPinnedCertHashes looks too short (expected 64+ hex chars)."

echo "✅ Release.xcconfig validated: API URL and cert hash look real."
