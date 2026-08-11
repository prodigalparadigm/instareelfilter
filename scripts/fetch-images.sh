#!/usr/bin/env bash
# reel-to-skill - Part 1 (image branch) - Fetch a photo/carousel post
# Instagram carousels have no video, so yt-dlp can't grab them. This uses
# gallery-dl for the images and yt-dlp --flat-playlist for the caption/meta.
# Same anonymous-first, one-cookie-retry-then-stop contract as fetch.sh.
#
# Usage:   fetch-images.sh <post-url>
# Output:  saves NN.jpg (carousel order) + caption.txt + meta.json into
#          ~/reel-to-skill/inbox/<author>-<date>/ and prints a RESULT block.
#
# Exit codes: 0 success - 2 login required after cookie retry - 3 usage/other
set -uo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "RESULT: ERROR usage: fetch-images.sh <post-url>" >&2
  exit 3
fi

for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH
command -v uvx >/dev/null 2>&1 || { echo "RESULT: ERROR uvx not found." >&2; exit 3; }

INBOX="$HOME/reel-to-skill/inbox"; mkdir -p "$INBOX"

login_error() {
  grep -qiE 'log[ -]?in|sign[ -]?in|authenticat|requires.*account|redirect to login|rate.?limit' <<<"$1"
}

# --- Step A: caption + author via yt-dlp --flat-playlist (usually anonymous) ---
YT_COOKIES=()
ytmeta() {
  local err out rc; err="$(mktemp)"
  out="$(uvx yt-dlp ${YT_COOKIES[@]+"${YT_COOKIES[@]}"} -J --flat-playlist --no-warnings "$URL" 2>"$err")"; rc=$?
  if [ $rc -ne 0 ] && [ ${#YT_COOKIES[@]} -eq 0 ] && login_error "$(cat "$err")"; then
    YT_COOKIES=(--cookies-from-browser chrome)
    out="$(uvx yt-dlp ${YT_COOKIES[@]+"${YT_COOKIES[@]}"} -J --flat-playlist --no-warnings "$URL" 2>"$err")"; rc=$?
  fi
  LAST_ERR="$(cat "$err")"; rm -f "$err"; printf '%s' "$out"; return $rc
}

echo "Fetching caption/metadata (anonymous)..." >&2
JSON="$(ytmeta)"; rc=$?
JSONFILE="$(mktemp)"; printf '%s' "$JSON" > "$JSONFILE"
trap 'rm -f "$JSONFILE"' EXIT

# Parse author (handle, not numeric id), date, caption, id. Tolerate empty JSON.
read -r AUTHOR DATE ID < <(python3 - "$JSONFILE" <<'PY'
import json, sys, re
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    data = {}
def handle():
    uid = (data.get("uploader_id") or "").lstrip("@")
    if uid and not uid.isdigit(): return uid
    for url in (data.get("uploader_url"), data.get("channel_url")):
        if url:
            slug = url.rstrip("/").split("/")[-1].lstrip("@")
            if slug and not slug.isdigit(): return slug
    m = re.search(r"[Vv]ideo by (\S+)|[Pp]ost by (\S+)", data.get("title") or "")
    if m: return (m.group(1) or m.group(2)).lstrip("@")
    return data.get("uploader") or data.get("channel") or uid or "unknown"
author = re.sub(r"[^A-Za-z0-9._-]+", "-", handle()).strip("-._").lower() or "unknown"
ud = data.get("upload_date")
date = f"{ud[:4]}-{ud[4:6]}-{ud[6:8]}" if ud and len(ud) == 8 else ""
print(author, date or "NODATE", data.get("id") or "post")
PY
)
[ "$DATE" = "NODATE" ] && DATE="$(date +%F)"
DEST="$INBOX/${AUTHOR}-${DATE}"; mkdir -p "$DEST"

python3 - "$DEST" "$URL" "$JSONFILE" "$AUTHOR" <<'PY'
import json, sys, os
dest, url, jsonfile, author = sys.argv[1:5]
try:
    data = json.load(open(jsonfile))
except Exception:
    data = {}
with open(os.path.join(dest, "caption.txt"), "w") as f:
    f.write((data.get("description") or "").rstrip() + "\n")
meta = {
    "author": author,
    "author_display": data.get("uploader") or "",
    "url": url,
    "post_type": "image_carousel",
    "image_count": len(data.get("entries") or []) or None,
    "upload_date": data.get("upload_date"),
    "id": data.get("id"),
}
json.dump(meta, open(os.path.join(dest, "meta.json"), "w"), indent=2)
PY

# --- Step B: images via gallery-dl. Name by {num} so slides stay in order. ----
echo "Downloading carousel images..." >&2
GD_COOKIES=()
gdl() {
  local err rc; err="$(mktemp)"
  uvx gallery-dl ${GD_COOKIES[@]+"${GD_COOKIES[@]}"} -D "$DEST" -f "{num:>02}.{extension}" "$URL" 2>"$err" >/dev/null; rc=$?
  if [ $rc -ne 0 ] && [ ${#GD_COOKIES[@]} -eq 0 ] && login_error "$(cat "$err")"; then
    echo "NOTE: gallery-dl hit a login wall; retrying once with --cookies-from-browser chrome" >&2
    GD_COOKIES=(--cookies-from-browser chrome)
    uvx gallery-dl ${GD_COOKIES[@]+"${GD_COOKIES[@]}"} -D "$DEST" -f "{num:>02}.{extension}" "$URL" 2>"$err" >/dev/null; rc=$?
  fi
  LAST_ERR="$(cat "$err")"; rm -f "$err"; return $rc
}
gdl; rc=$?

IMAGES="$(ls "$DEST"/*.jpg "$DEST"/*.png "$DEST"/*.webp 2>/dev/null | sort)"
if [ $rc -ne 0 ] || [ -z "$IMAGES" ]; then
  if login_error "${LAST_ERR:-}"; then
    echo "RESULT: LOGIN_REQUIRED gallery-dl needs a login even after cookie retry. Stopping." >&2
    exit 2
  fi
  echo "RESULT: ERROR gallery-dl could not fetch images. See stderr above." >&2
  exit 3
fi

COUNT="$(printf '%s\n' "$IMAGES" | wc -l | tr -d ' ')"
cat <<EOF
RESULT: OK
DEST=$DEST
CAPTION=$DEST/caption.txt
META=$DEST/meta.json
AUTHOR=$AUTHOR
DATE=$DATE
IMAGE_COUNT=$COUNT
URL=$URL
EOF
printf '%s\n' "$IMAGES" | sed 's/^/IMAGE=/'
exit 0
