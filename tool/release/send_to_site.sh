#!/usr/bin/env bash
# Sends a release's packages and version.json to lifeos.com.tr, then waits
# until the site publishes them:
#
#   DEPLOY_KEY=… KNOWN_HOSTS=… bash tool/release/send_to_site.sh <folder> <app>
#
# The key can only drop files into this app's incoming folder on the
# server; the server publishes them once each package's size and SHA-256
# match version.json (lifeosweb: sunucu/uygulama-yayini). READY goes last:
# it is what starts the server's check.
set -euo pipefail
folder="$1"
app="$2"
version="$(jq -r .latest "$folder/version.json")"

work="${RUNNER_TEMP:-$(mktemp -d)}"
install -m 600 /dev/null "$work/deploy_key"
printf '%s\n' "$DEPLOY_KEY" > "$work/deploy_key"
printf '%s\n' "$KNOWN_HOSTS" > "$work/known_hosts"
ssh="ssh -i $work/deploy_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$work/known_hosts -o ConnectTimeout=20"

# Tried again a few times: sshd turns away new connections while bots
# crowd it.
send() {
  for attempt in 1 2 3 4 5 6; do
    rsync "$@" && return 0
    echo "Sunucuya gönderilemedi ($attempt. deneme); biraz sonra yeniden."
    sleep $((attempt * 20))
  done
  return 1
}
send -rt -e "$ssh" "$folder/" lifeos-uygulama@sbyazilim.info:
touch "$work/READY"
send -t -e "$ssh" "$work/READY" lifeos-uygulama@sbyazilim.info:READY
rm -f "$work/deploy_key"

url="https://lifeos.com.tr/downloads/$app/version.json"
seen=''
for attempt in $(seq 1 30); do
  seen="$(curl -fsS -H 'Cache-Control: no-cache' "$url?t=$attempt$RANDOM" | jq -r .latest || true)"
  [ "$seen" = "$version" ] && break
  sleep 10
done
if [ "$seen" != "$version" ]; then
  echo "::error::lifeos.com.tr $app için $version göstermiyor (${seen:-yok})."
  exit 1
fi
for platform in $(jq -r '.files | keys[]' "$folder/version.json"); do
  name="$(jq -r ".files.$platform.name" "$folder/version.json")"
  size="$(jq -r ".files.$platform.size" "$folder/version.json")"
  # A file the site does not have still answers 200, with the site's own
  # page: the package is there only if its size is right.
  served="$(curl -fsSI "https://lifeos.com.tr/downloads/$app/$name" | tr -d '\r' | sed -nE 's/^[Cc]ontent-[Ll]ength: *([0-9]+)$/\1/p' | tail -1)"
  if [ "$served" != "$size" ]; then
    echo "::error::$name $size bayt olmalı, site ${served:-?} bayt veriyor."
    exit 1
  fi
  echo "$platform: $version yayında, https://lifeos.com.tr/downloads/$app/$name"
done
