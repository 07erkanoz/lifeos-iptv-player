#!/usr/bin/env bash
# Writes the version.json lifeos.com.tr serves at /downloads/<app>/ for the
# packages in <folder>: what the site's download buttons show, and what the
# server checks the packages against before publishing them.
#
#   bash tool/release/version_json.sh <app> <prefix> <version> <build> <folder>
#
# Release notes come from release/notes_tr.md and release/notes_en.md.
# MIN_SUPPORTED, when set, adds minSupported.
set -euo pipefail
app="$1" prefix="$2" version="$3" build="$4" folder="$5"
notes() { if [ -f "release/notes_$1.md" ]; then cat "release/notes_$1.md"; fi; }
files='{}'
downloads='{}'
for pair in windows:Windows-x64-Setup.exe linux:Linux-x64.tar.gz android:Android.apk; do
  platform="${pair%%:*}"
  name="$prefix-$version-${pair#*:}"
  [ -f "$folder/$name" ] || continue
  size="$(stat -c %s "$folder/$name")"
  sha="$(sha256sum "$folder/$name" | cut -d' ' -f1)"
  files="$(jq --arg p "$platform" --arg n "$name" --argjson s "$size" --arg h "$sha" \
    '. + {($p): {name: $n, size: $s, sha256: $h}}' <<< "$files")"
  downloads="$(jq --arg p "$platform" --arg u "https://lifeos.com.tr/downloads/$app/$name" \
    '. + {($p): $u}' <<< "$downloads")"
done
[ "$files" != '{}' ] || { echo "$folder içinde paket yok." >&2; exit 1; }
jq -n --arg v "$version" --argjson b "$build" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg min "${MIN_SUPPORTED:-}" --arg tr "$(notes tr)" --arg en "$(notes en)" \
  --arg page "https://lifeos.com.tr/$app" --argjson files "$files" --argjson downloads "$downloads" \
  '{latest: $v, build: $b, releasedAt: $at} + (if $min == "" then {} else {minSupported: $min} end)
   + {notes: {tr: $tr, en: $en}, page: $page, downloads: $downloads, files: $files}'
