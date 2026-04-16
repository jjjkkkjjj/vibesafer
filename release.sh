#!/usr/bin/env bash
# release.sh — Tag, version-bump, and push a new release.
#
# Usage:
#   ./release.sh <version>       # e.g. ./release.sh 0.3.0
#
# What it does:
#   1. Validates the working tree is clean
#   2. Updates version in Cargo.toml
#   3. Runs tests and clippy inside Docker
#   4. Commits the version bump
#   5. Creates a git tag (vX.Y.Z)
#   6. Pushes main branch and tag to origin (tag push triggers CI)
#
# On any failure before the tag push, all local changes are rolled back.
# If the tag has already been pushed to origin, it is deleted from remote too.

set -euo pipefail

# ── Argument validation ───────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 <version>"
  echo "  e.g.  $0 0.3.0"
  exit 1
}

[[ $# -eq 1 ]] || usage
VERSION="$1"
TAG="v${VERSION}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be in X.Y.Z format (e.g. 0.3.0)" >&2
  exit 1
fi

# ── Snapshot current state ────────────────────────────────────────────────────
ORIGINAL_VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')

if [[ "${VERSION}" == "${ORIGINAL_VERSION}" ]]; then
  echo "Error: Cargo.toml already has version ${VERSION}." >&2
  exit 1
fi

# ── Progress flags (used in rollback) ────────────────────────────────────────
CARGO_UPDATED=false
COMMITTED=false
TAGGED=false
REMOTE_TAG_PUSHED=false
SUCCESS=false

# ── Rollback handler ─────────────────────────────────────────────────────────
rollback() {
  if [[ "${SUCCESS}" == true ]]; then return; fi

  echo ""
  echo "=== Error detected — rolling back ==="

  if [[ "${REMOTE_TAG_PUSHED}" == true ]]; then
    echo "► Deleting remote tag ${TAG}..."
    git push origin ":refs/tags/${TAG}" || echo "  Warning: could not delete remote tag ${TAG}"
  fi

  if [[ "${TAGGED}" == true ]]; then
    echo "► Deleting local tag ${TAG}..."
    git tag -d "${TAG}" || true
  fi

  if [[ "${COMMITTED}" == true ]]; then
    echo "► Reverting version-bump commit..."
    git reset --soft HEAD~1
  fi

  if [[ "${CARGO_UPDATED}" == true ]]; then
    echo "► Restoring Cargo.toml..."
    git checkout -- Cargo.toml
  fi

  echo "=== Rollback complete ==="
}

trap rollback EXIT

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

if git tag | grep -q "^${TAG}$"; then
  echo "Error: local tag ${TAG} already exists. Delete it first: git tag -d ${TAG}" >&2
  exit 1
fi

echo "Releasing ${TAG}  (current: v${ORIGINAL_VERSION})"
echo ""

# ── 1. Update Cargo.toml ─────────────────────────────────────────────────────
echo "► Updating Cargo.toml: ${ORIGINAL_VERSION} → ${VERSION}"
# perl -i is portable across macOS and Linux (avoids sed -i flag differences)
perl -i -pe "s/^version = \"${ORIGINAL_VERSION}\"/version = \"${VERSION}\"/" Cargo.toml
CARGO_UPDATED=true

# ── 2. Build / test / lint ───────────────────────────────────────────────────
echo "► Running tests..."
./cargo-docker test

echo "► Running clippy..."
./cargo-docker clippy -- -D warnings

# ── 3. Commit ────────────────────────────────────────────────────────────────
echo "► Committing version bump..."
git add Cargo.toml
git commit -m "chore: bump version to ${TAG}"
COMMITTED=true

# ── 4. Tag ───────────────────────────────────────────────────────────────────
echo "► Creating tag ${TAG}..."
git tag "${TAG}"
TAGGED=true

# ── 5. Push ──────────────────────────────────────────────────────────────────
echo "► Pushing main to origin..."
git push origin main

echo "► Pushing tag ${TAG} to origin (triggers CI release)..."
git push origin "${TAG}"
REMOTE_TAG_PUSHED=true

# ── Done ─────────────────────────────────────────────────────────────────────
SUCCESS=true
echo ""
echo "✓ ${TAG} released successfully."
echo "  CI will build binaries and publish the GitHub Release automatically."
echo "  Track progress: https://github.com/jjjkkkjjj/vibeguardian/actions"
