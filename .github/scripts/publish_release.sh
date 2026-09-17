#!/usr/bin/env bash
set -e

CHANGES="${INPUT_RELEASE_NOTES:-}"
if [ -z "$CHANGES" ] || [ "$CHANGES" = "Automated build from GitHub Actions." ]; then
  CHANGES="### 🚀 What's New:
- **WhatsApp Style Phone Search**: Connect with anyone by searching their 10-digit mobile number directly.
- **Lean APK Builds**: Android app package optimized down to ~20MB (arm64-v8a) from 73MB.
- **App Store Web Hub**: Dynamic web page displaying all versions with direct APK/IPA downloads.

### 🐛 Bug Fixes & Improvements:
- **Android In-App Update**: Fixed 'Update Now' button opening in browser.
- **iOS Phone Auth Crash**: Fixed unhandled URL scheme on iPhone by configuring CFBundleURLSchemes.
- **Direct Home Landing**: Bypassed onboarding QR screen; users land directly into HomeScreen."
fi

BODY_CONTENT="## ${LABEL}: Astra ${TAG_NAME}

${CHANGES}

Commit: \`${GITHUB_SHA}\`
Ready for Android direct install and iOS Sideloadly / AltStore / TrollStore."

PRERELEASE_FLAG=""
if [ "$IS_PRERELEASE" = "true" ]; then
  PRERELEASE_FLAG="--prerelease"
fi

echo "Publishing release for $TAG_NAME with assets:"
ls -la release-dist/

# Check if release already exists (including drafts)
if gh release view "$TAG_NAME" > /dev/null 2>&1; then
  echo "Release $TAG_NAME exists. Uploading assets and publishing (undraft)..."
  gh release upload "$TAG_NAME" release-dist/* --clobber
  gh release edit "$TAG_NAME" --draft=false $PRERELEASE_FLAG
else
  echo "Creating and publishing release $TAG_NAME..."
  gh release create "$TAG_NAME" release-dist/* \
    --title "$TITLE" \
    --notes "$BODY_CONTENT" \
    --draft=false \
    $PRERELEASE_FLAG
fi
