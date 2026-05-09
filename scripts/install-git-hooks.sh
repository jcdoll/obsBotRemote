#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

chmod +x .githooks/pre-commit .githooks/pre-push scripts/lint-swift-format.sh
git config core.hooksPath .githooks
echo "Git hooks installed from .githooks"
