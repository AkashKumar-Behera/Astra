#!/usr/bin/env bash
set -e

CHANGES="${INPUT_RELEASE_NOTES:-}"

# If no manual workflow dispatch notes, try reading the git tag message
if [ -z "$CHANGES" ] || [ "$CHANGES" = "Automated build from GitHub Actions." ]; then
  TAG_MSG=$(git tag -l --format='%(contents)' "$TAG_NAME" 2>/dev/null || echo "")
  if [ -n "$TAG_MSG" ]; then
    CHANGES="$TAG_MSG"
  else
    COMMIT_MSG=$(git log -1 --pretty=%B 2>/dev/null || echo "")
    CHANGES="$COMMIT_MSG"
  fi
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
