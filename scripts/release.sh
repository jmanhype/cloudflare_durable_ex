#!/usr/bin/env bash
set -e

# Check if the version is provided
if [ -z "$1" ]; then
  echo "Error: No version number provided"
  echo "Usage: ./scripts/release.sh VERSION"
  exit 1
fi

VERSION=$1
TODAY=$(date +%Y-%m-%d)

# Validate version format (vX.Y.Z or X.Y.Z)
if [[ ! $VERSION =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Invalid version format. Please use X.Y.Z or vX.Y.Z"
  exit 1
fi

# Strip 'v' prefix if present
if [[ $VERSION == v* ]]; then
  VERSION="${VERSION:1}"
fi

echo "Preparing release for version $VERSION..."

# 1. Update version in mix.exs
sed -i '' "s/@version \"[0-9]*\.[0-9]*\.[0-9]*\"/@version \"$VERSION\"/g" mix.exs
echo "✅ Updated version in mix.exs"

# 2. Update CHANGELOG.md - change Unreleased to new version
sed -i '' "s/## \[Unreleased\]/## [Unreleased]\n\n## [$VERSION] - $TODAY/g" CHANGELOG.md
echo "✅ Updated CHANGELOG.md with new version date"

# 3. Update links in CHANGELOG.md
# Check if the previous version exists in the file to determine if this is the first release
PREV_VERSION=$(grep -o '\[[0-9]*\.[0-9]*\.[0-9]*\]' CHANGELOG.md | head -1 | sed 's/\[//;s/\]//')
if [ -n "$PREV_VERSION" ]; then
  # Add or update the Unreleased link
  if grep -q "\[Unreleased\]:" CHANGELOG.md; then
    sed -i '' "s|\[Unreleased\]:.*|[Unreleased]: https://github.com/jmanhype/cloudflare_durable_ex/compare/v$VERSION...HEAD|g" CHANGELOG.md
  else
    echo "[Unreleased]: https://github.com/jmanhype/cloudflare_durable_ex/compare/v$VERSION...HEAD" >> CHANGELOG.md
  fi
  
  # Add new version link
  if ! grep -q "\[$VERSION\]:" CHANGELOG.md; then
    echo "[$VERSION]: https://github.com/jmanhype/cloudflare_durable_ex/compare/v$PREV_VERSION...v$VERSION" >> CHANGELOG.md
  fi
else
  # First release - just add the Unreleased and version links
  echo "[Unreleased]: https://github.com/jmanhype/cloudflare_durable_ex/compare/v$VERSION...HEAD" >> CHANGELOG.md
  echo "[$VERSION]: https://github.com/jmanhype/cloudflare_durable_ex/releases/tag/v$VERSION" >> CHANGELOG.md
fi
echo "✅ Updated CHANGELOG.md links"

# 4. Run formatter to ensure consistent formatting
mix format
echo "✅ Formatted code"

# 5. Make sure tests pass
echo "Running tests..."
mix test
echo "✅ Tests passed"

# 6. Compile documentation to ensure it works
mix docs
echo "✅ Documentation compiled successfully"

# 7. Git operations
git add mix.exs CHANGELOG.md
git commit -m "Release v$VERSION"
git tag -a "v$VERSION" -m "Release v$VERSION"
echo "✅ Created git commit and tag for v$VERSION"

echo ""
echo "Release v$VERSION is ready!"
echo ""
echo "Next steps:"
echo "  1. Review the changes with 'git show'"
echo "  2. Push the changes with 'git push origin main --tags'"
echo "  3. GitHub Actions will automatically publish to Hex.pm"
echo ""
echo "Or reset with 'git reset --hard HEAD~1 && git tag -d v$VERSION' if needed." 