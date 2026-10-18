#!/usr/bin/env bash
# Download the data OTP needs into otp/data/:
#   - GTFS feeds from 511.org (AC Transit by default)
#   - An East Bay OpenStreetMap extract, clipped from Geofabrik's NorCal file
#
# Usage:   ./otp/fetch_data.sh
# Env:     API_511_TOKEN   (required; read from .env at repo root if present)
#          OPERATORS       (optional; space-separated 511 operator ids, default "AC")
#          OSM_BBOX        (optional; west,south,east,north)
# Needs:   curl, unzip, osmium (brew install osmium-tool)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$ROOT/otp/data"
CACHE="$ROOT/otp/cache"

if [[ -f "$ROOT/.env" ]]; then
  set -a; . "$ROOT/.env"; set +a
fi

: "${API_511_TOKEN:?Set API_511_TOKEN in .env (get one at https://511.org/open-data/token)}"
OPERATORS="${OPERATORS:-AC}"
# Richmond/El Cerrito to San Leandro, Bay shoreline to Orinda.
OSM_BBOX="${OSM_BBOX:--122.42,37.70,-122.10,38.02}"
NORCAL_URL="https://download.geofabrik.de/north-america/us/california/norcal-latest.osm.pbf"

for cmd in curl unzip osmium; do
  command -v "$cmd" >/dev/null || { echo "Missing '$cmd'." >&2; exit 1; }
done

mkdir -p "$DATA" "$CACHE"

# --- GTFS ---------------------------------------------------------------
# OTP picks up any zip in the graph dir whose name contains "gtfs".
for op in $OPERATORS; do
  out="$DATA/$(echo "$op" | tr "[:upper:]" "[:lower:]")-gtfs.zip"
  tmp="$out.part"
  echo "GTFS: $op"
  code=$(curl -sS -L -o "$tmp" -w '%{http_code}' \
    "https://api.511.org/transit/datafeeds?api_key=${API_511_TOKEN}&operator_id=${op}")
  if [[ "$code" != "200" ]] || ! unzip -tq "$tmp" >/dev/null 2>&1; then
    echo "  failed (HTTP $code): $(head -c 200 "$tmp")" >&2
    rm -f "$tmp"
    exit 1
  fi
  mv "$tmp" "$out"
  echo "  -> $out ($(du -h "$out" | cut -f1))"
done

# --- OSM ----------------------------------------------------------------
# The NorCal file (~650 MB) is cached and only re-downloaded when Geofabrik
# has a newer copy (-z).
norcal="$CACHE/norcal-latest.osm.pbf"
echo "OSM: NorCal extract"
if [[ -f "$norcal" ]]; then
  curl -sS -L -z "$norcal" -o "$norcal" "$NORCAL_URL"
else
  curl -L --fail -# -o "$norcal.part" "$NORCAL_URL" && mv "$norcal.part" "$norcal"
fi

out="$DATA/east-bay.osm.pbf"
echo "OSM: clipping to $OSM_BBOX"
osmium extract --bbox "$OSM_BBOX" --strategy smart --overwrite -o "$out" "$norcal"
echo "  -> $out ($(du -h "$out" | cut -f1))"

echo "Done. Files in $DATA:"
ls -lh "$DATA"
