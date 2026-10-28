#!/usr/bin/env bash
# Packs the built Linux bundle as artifacts/<PREFIX>-<version>-Linux-x64.tar.gz:
# one folder holding the bundle, kur.sh, and what kur.sh needs to add the
# app to the menu. The app's names come from packaging/linux/uygulama.conf.
set -euo pipefail
cd "$(dirname "$0")/../.."
. packaging/linux/uygulama.conf
version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+[[:space:]]*$/\1/p' pubspec.yaml)"
test -n "$version" || { echo "pubspec.yaml sürümü okunamadı." >&2; exit 1; }
bundle=build/linux/x64/release/bundle
test -x "$bundle/$BINARY" || { echo "Linux bundle derlenmemiş." >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
root="$stage/$PREFIX"
mkdir -p "$root/kurulum"
cp -a "$bundle/." "$root/"
cp packaging/linux/uygulama.conf "$root/kurulum/"
magick "$ICON" -resize 512x512 "$root/kurulum/icon.png" 2>/dev/null \
  || convert "$ICON" -resize 512x512 "$root/kurulum/icon.png" 2>/dev/null \
  || cp "$ICON" "$root/kurulum/icon.png"
install -m 755 packaging/linux/kur.sh "$root/kur.sh"
mkdir -p artifacts
out="artifacts/$PREFIX-$version-Linux-x64.tar.gz"
tar -C "$stage" --owner=0 --group=0 --numeric-owner -czf "$out" "$PREFIX"
echo "$out"
