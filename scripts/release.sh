#!/bin/bash
# Makes the downloadable app for a GitHub release: dist/AgentBuddy-<version>.zip
# (Apple silicon + Intel). Attach the zip to the release on GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh --universal
VERSION=$(cat VERSION)
mkdir -p dist
rm -f "dist/AgentBuddy-$VERSION.zip"
ditto -c -k --keepParent build/AgentBuddy.app "dist/AgentBuddy-$VERSION.zip"
echo "dist/AgentBuddy-$VERSION.zip"
