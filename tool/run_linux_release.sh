#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$project_dir/build/linux/x64/release/bundle"
if [[ ! -x "$bundle/lifeostv" ]]; then
  printf '%s\n' 'Release bulunamadı. Proje dizininde flutter build linux --release çalıştırın.' >&2
  exit 1
fi
cd -- "$bundle"
exec ./lifeostv "$@"
