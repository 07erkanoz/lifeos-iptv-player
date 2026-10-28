#!/bin/sh
# Puts the app in this folder under ~/.local/share and into the app menu.
# No administrator rights; to update, run the kur.sh of the newer version
# the same way. To remove: kur.sh --kaldir
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$here/kurulum/uygulama.conf"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
target="$data/$SLUG"
desktop="$data/applications/$APP_ID.desktop"
icon="$data/icons/hicolor/512x512/apps/$APP_ID.png"

if [ "${1:-}" = --kaldir ]; then
  rm -rf "$target" "$desktop" "$icon"
  echo "$NAME kaldırıldı. Ayarlarınız ve verileriniz yerinde duruyor."
  exit 0
fi

# Copied beside the old one first, then swapped, so a half-copied app never
# replaces a working one.
rm -rf "$target.yeni" "$target.eski"
mkdir -p "$target.yeni"
cp -a "$here/." "$target.yeni/"
if [ -d "$target" ]; then mv "$target" "$target.eski"; fi
mv "$target.yeni" "$target"
rm -rf "$target.eski"

mkdir -p "$(dirname "$icon")" "$(dirname "$desktop")"
cp "$target/kurulum/icon.png" "$icon"
cat > "$desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$NAME
Comment=$COMMENT
Comment[tr]=$COMMENT_TR
Exec="$target/$BINARY" %U
Icon=$APP_ID
Terminal=false
Categories=$CATEGORIES
StartupWMClass=$APP_ID
DESKTOP
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$data/applications" 2>/dev/null || true

echo "$NAME kuruldu: $target"
echo "Uygulama menüsünden açabilirsiniz."
# Libraries the app needs from the system (NEEDS_LIB, space-separated).
if [ -n "${NEEDS_LIB:-}" ] && command -v ldconfig >/dev/null 2>&1; then
  missing=''
  for lib in $NEEDS_LIB; do
    ldconfig -p 2>/dev/null | grep -q "$lib" || missing="$missing $lib"
  done
  if [ -n "$missing" ]; then
    echo
    echo "Uyarı:$missing bulunamadı. $NEEDS_HINT"
  fi
fi
