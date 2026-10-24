#!/bin/zsh
# Probes the camera while the Mac is joined to its Wi-Fi Direct network
# (Ctrl w/ Smartphone). Runs offline and writes everything to a log file.
#
# Usage: scripts/probe-wifi-direct.sh [log-file]

cd "$(dirname "$0")/.." || exit 1
log="${1:-$HOME/Desktop/shutterdrop-wifi-direct.log}"
exec > >(tee "$log") 2>&1

echo "== $(date) =="
echo "== Wi-Fi network =="
networksetup -getairportnetwork en0 2>/dev/null || ipconfig getsummary en0 | grep -E " SSID"
echo "== Mac address and router (the camera, on Wi-Fi Direct) =="
ipconfig getifaddr en0
camera=$(route -n get default 2>/dev/null | awk '/gateway/ {print $2}')
echo "gateway: ${camera:-none}"
[ -n "$camera" ] || { echo "No gateway; is the Mac joined to the camera's DIRECT-… network?"; exit 1; }

echo "== Ping =="
ping -c 3 -t 5 "$camera" | tail -2

echo "== Open ports =="
for port in 80 443 8080 10000 15740 61000 64321; do
  nc -z -G 2 "$camera" "$port" 2>/dev/null && echo "$port open" || echo "$port closed"
done

echo "== SSDP discovery (10 s) =="
.build/debug/sdprobe discover --seconds 10

echo "== Device descriptions =="
.build/debug/sdprobe discover --seconds 4 2>/dev/null | awk '/LOCATION:/ {print $2}' | sort -u | while read -r url; do
  echo "--- $url"
  curl -s -m 5 "$url" | head -c 6000
  echo
done

echo "== PTP/IP connect (40 s, take 2 photos with the camera's shutter now) =="
.build/debug/sdprobe connect "$camera" &
pid=$!
sleep 40
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

echo "== Done $(date) =="
echo "Log saved to $log. Switch back to your home Wi-Fi."
