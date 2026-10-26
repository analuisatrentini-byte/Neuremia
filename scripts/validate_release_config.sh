#!/usr/bin/env bash
# Validates that Release.xcconfig has real values before archiving.
# Run in CI pre-archive step: bash scripts/validate_release_config.sh
set -euo pipefail

XCCONFIG="Neuremia/Config/Release.xcconfig"
PROJECT_FILE="Neuremia.xcodeproj/project.pbxproj"
RELEASE_ENTITLEMENTS="Neuremia/NeuremiaRelease.entitlements"

error() { echo "❌ $1" >&2; exit 1; }
errors=()

add_error() {
  errors+=("❌ $1")
}

CERT_HASH=$(grep "NeuremiaPinnedCertHashes" "$XCCONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')
API_URL=$(grep "NeuremiaAPIBaseURL" "$XCCONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')

[[ "$API_URL" == *"your-domain"* ]] && add_error "Release.xcconfig: NeuremiaAPIBaseURL still has placeholder value."
[[ "$CERT_HASH" == *"REPLACE_WITH"* ]] && add_error "Release.xcconfig: NeuremiaPinnedCertHashes is still a placeholder. Leave it empty for standard TLS or provide real 64-char hex hashes."
if [[ -n "$CERT_HASH" ]]; then
  IFS=',' read -ra HASHES <<< "$CERT_HASH"
  for hash in "${HASHES[@]}"; do
    [[ "$hash" =~ ^[0-9a-fA-F]{64}$ ]] || add_error "Release.xcconfig: NeuremiaPinnedCertHashes contains an invalid SHA-256 hash."
  done
fi

[[ -f "$RELEASE_ENTITLEMENTS" ]] || add_error "Missing $RELEASE_ENTITLEMENTS."
grep -q "CODE_SIGN_ENTITLEMENTS = $RELEASE_ENTITLEMENTS;" "$PROJECT_FILE" || add_error "Release target does not point to $RELEASE_ENTITLEMENTS. In Xcode, set Target Neuremia > Build Settings > Code Signing Entitlements > Release."
if [[ -f "$RELEASE_ENTITLEMENTS" ]]; then
  grep -q "aps-environment" "$RELEASE_ENTITLEMENTS" || add_error "$RELEASE_ENTITLEMENTS: missing aps-environment."
  grep -q "com.apple.developer.healthkit" "$RELEASE_ENTITLEMENTS" || add_error "$RELEASE_ENTITLEMENTS: missing HealthKit entitlement."
  grep -q "com.apple.developer.healthkit.background-delivery" "$RELEASE_ENTITLEMENTS" || add_error "$RELEASE_ENTITLEMENTS: missing HealthKit background delivery entitlement."
fi

if (( ${#errors[@]} > 0 )); then
  printf '%s\n' "${errors[@]}" >&2
  exit 1
fi

echo "✅ Release config validated: API URL configured, entitlements wired, certificate pinning optional."
