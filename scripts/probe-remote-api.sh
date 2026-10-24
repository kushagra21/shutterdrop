#!/bin/zsh
# Probes Sony's Camera Remote API (ScalarWebAPI) while the Mac is joined to the
# camera's Wi-Fi Direct network (Ctrl w/ Smartphone). Runs offline and writes
# everything to a log file. Takes ONE photo via the API to test the postview.
#
# Usage: scripts/probe-remote-api.sh [log-file]

log="${1:-$HOME/Desktop/shutterdrop-remote-api.log}"
out="$HOME/Desktop/shutterdrop-postview"
exec > >(tee "$log") 2>&1

camera=$(route -n get default 2>/dev/null | awk '/gateway/ {print $2}')
echo "== $(date) camera ${camera:-none} =="
[ -n "$camera" ] || { echo "No gateway; is the Mac joined to the camera's DIRECT-… network?"; exit 1; }

echo "== Device description =="
dd=$(curl -s -m 5 "http://$camera:64321/dd.xml")
echo "$dd"
base=$(echo "$dd" | grep -oE '<av:X_ScalarWebAPI_ActionList_URL>[^<]+' | head -1 | sed 's/.*>//')
base=${base:-http://$camera:10000/sony}
echo "API base: $base"

# rpc <service> <method> <params-json> [version] [timeout]
rpc() {
  echo "--> $1.$2 $3"
  curl -s -m "${5:-10}" -H 'Content-Type: application/json' \
    -d "{\"method\":\"$2\",\"params\":$3,\"id\":1,\"version\":\"${4:-1.0}\"}" "$base/$1"
  echo
}

echo "== Capabilities =="
rpc camera getVersions '[]'
rpc camera getApplicationInfo '[]'
apis=$(rpc camera getAvailableApiList '[]')
echo "$apis"
rpc system getVersions '[]'
rpc avContent getVersions '[]'

if echo "$apis" | grep -q '"startRecMode"'; then
  rpc camera startRecMode '[]'
  sleep 2
  rpc camera getAvailableApiList '[]'
fi

echo "== Postview size =="
rpc camera getAvailablePostviewImageSize '[]'
rpc camera setPostviewImageSize '["Original"]'
rpc camera getPostviewImageSize '[]'

echo "== Current state =="
rpc camera getEvent '[false]' 1.0
rpc camera getEvent '[false]' 1.2

echo "== Shutter-button test (45 s): TAKE 2 PHOTOS WITH THE CAMERA'S OWN SHUTTER NOW =="
end=$((SECONDS + 45))
while [ $SECONDS -lt $end ]; do
  echo "[$(date +%T)]"
  rpc camera getEvent '[true]' 1.0 15
done

echo "== API capture test: the camera takes one photo now =="
shot=$(rpc camera actTakePicture '[]' 1.0 30)
echo "$shot"
url=$(echo "$shot" | grep -oE 'http://[^"]+' | head -1)
if [ -n "$url" ]; then
  echo "Downloading postview $url"
  curl -s -m 60 -D - -o "$out.jpg" "$url" | head -20
  ls -la "$out.jpg"
  file "$out.jpg"
  sips -g pixelWidth -g pixelHeight "$out.jpg" 2>/dev/null
fi
rpc camera getEvent '[false]' 1.0

echo "== Done $(date) =="
echo "Log saved to $log. Switch back to your home Wi-Fi."
