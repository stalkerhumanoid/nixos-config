#!/usr/bin/env bash
set -eu

PLAYLIST_URL="https://www.youtube.com/playlist?list=FLlzHLzHLLCBwygmRGWerHOg"
OUTPUT_DIR="/mnt/data/Libraries/Videos/YouTube/Favorites"
YT_DLP_METADATA_DIR="$OUTPUT_DIR/yt-dlp"
ARCHIVE_FILE="$YT_DLP_METADATA_DIR/downloaded.txt"
UNAVAILABLE_FILE="$YT_DLP_METADATA_DIR/unavailable.txt"
OUTPUT_FILE="$OUTPUT_DIR/%(playlist_autonumber)s - %(title)s {%(uploader)s - %(upload_date)s}.%(ext)s"
TEMP_PLAYLIST_FILE="/tmp/youtube-downloader-playlist.json"
COOKIES_SOURCE="${COOKIES_SOURCE:-/run/agenix/youtube-cookies}"

# Authentication cookies are required: without them YouTube caps playlist
# pagination at 100 items on flagged IPs. Fail loudly if the file is missing.
if [ ! -f "$COOKIES_SOURCE" ]; then
    echo "Error: cookies file not found at $COOKIES_SOURCE" >&2
    exit 1
fi

# yt-dlp opens --cookies for writing so it can persist refreshed cookies, but
# agenix decrypts to mode 0400. Hand it a private writable copy instead. The
# refresh is discarded either way: the original is encrypted at rest and can't
# be updated in place, so re-export from the browser when these expire.
COOKIES_FILE="$(mktemp)"
trap 'rm -f "$COOKIES_FILE"' EXIT
cp "$COOKIES_SOURCE" "$COOKIES_FILE"

# Create the yt-dlp metadata dir if necessary
mkdir -p "$YT_DLP_METADATA_DIR"

# Save list of unavailable videos
yt-dlp --cookies "$COOKIES_FILE" --dump-json --flat-playlist --playlist-reverse "$PLAYLIST_URL" >"$TEMP_PLAYLIST_FILE"
jq -r 'select(.uploader == null) | (.playlist_autonumber |  tostring) + " - " + .id' "$TEMP_PLAYLIST_FILE" >"$UNAVAILABLE_FILE"
rm -f "$TEMP_PLAYLIST_FILE"

# Download all the available videos
yt-dlp -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best' \
    --cookies "$COOKIES_FILE" \
    --playlist-reverse \
    --download-archive "$ARCHIVE_FILE" \
    --write-info-json \
    --embed-metadata \
    -o "$OUTPUT_FILE" \
    "$PLAYLIST_URL"
