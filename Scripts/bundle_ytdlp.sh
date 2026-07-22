#!/bin/bash
set -euo pipefail

DEST="${1:-$(dirname "$0")/../Apps/Kinema/Resources}"
mkdir -p "$DEST"

if command -v yt-dlp >/dev/null 2>&1; then
  YTDLP=$(command -v yt-dlp)
elif [ -x /opt/homebrew/bin/yt-dlp ]; then
  YTDLP=/opt/homebrew/bin/yt-dlp
elif [ -x /usr/local/bin/yt-dlp ]; then
  YTDLP=/usr/local/bin/yt-dlp
else
  echo "yt-dlp not found. Install with: brew install yt-dlp"
  exit 1
fi

cp "$YTDLP" "$DEST/yt-dlp"
chmod +x "$DEST/yt-dlp"
echo "Bundled yt-dlp to $DEST/yt-dlp"
