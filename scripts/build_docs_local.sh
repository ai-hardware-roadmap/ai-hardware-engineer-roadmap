#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/prepare_docs.sh"

MKDOCS_ARGS=(build --config-file "$ROOT_DIR/mkdocs.yml" --site-dir "$ROOT_DIR/_site")
if [[ "${STRICT:-0}" == "1" ]]; then
  MKDOCS_ARGS+=(--strict)
fi

mkdocs "${MKDOCS_ARGS[@]}"

echo "Built site at $ROOT_DIR/_site"
