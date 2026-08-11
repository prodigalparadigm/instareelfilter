#!/usr/bin/env bash
# reel-to-skill - Part 1 - Fetch
# Anonymous Instagram-reel fetch via `uvx yt-dlp`. No login by default.
# On a login/auth error: retry ONCE with --cookies-from-browser chrome, then stop.
#
# Usage:   fetch.sh <reel-url>
# Output:  saves video + caption.txt + meta.json into
#          ~/reel-to-skill/inbox/<author>-<date>/
#          and prints a RESULT block for the orchestrating skill to parse.
#
# Exit codes:
#   0  success
#   2  login required even after the cookie retry  -> stop, tell the user
#   3  usage / other hard error
set -uo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "RESULT: ERROR usage: fetch.sh <reel-url>" >&2
  exit 3
fi

# --- locate uvx (installer puts it in ~/.local/bin; brew in /opt/homebrew/bin) ---
for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH
if ! command -v uvx >/dev/null 2>&1; then
  echo "RESULT: ERROR uvx not found. Install with: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 3
fi

INBOX="$HOME/reel-to-skill/inbox"
mkdir -p "$INBOX"

# COOKIE_ARGS is empty on the anonymous attempt; populated for the retry so that
# the later download reuses whatever got us past the metadata call.
COOKIE_ARGS=()

# Shared stderr sink. run_ytdlp is called inside $(...) (a subshell), so a shell
# *variable* set in there never reaches the parent - capture to a real file that
# survives the subshell, and read it back in the parent after each call.
ERRFILE="$(mktemp)"
trap 'rm -f "$ERRFILE" "${JSONFILE:-}"' EXIT

login_error() {
  # True if yt-dlp stderr looks like it needs a login / is rate-limited.
  grep -qiE 'log[ -]?in|sign[ -]?in|authenticat|requires.*account|cookies|rate.?limit|not available' <<<"$1"
}

# Run yt-dlp with current COOKIE_ARGS, capturing stderr. Retry once with Chrome
# cookies on a login-shaped failure. Echoes stdout; returns yt-dlp's status.
run_ytdlp() {
  local out rc
  # ${arr[@]+"${arr[@]}"} - bash 3.2 (macOS default) throws "unbound variable"
  # on a bare "${arr[@]}" when the array is empty under `set -u`.
  out="$(uvx yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} "$@" 2>"$ERRFILE")"; rc=$?
  if [ $rc -ne 0 ] && [ ${#COOKIE_ARGS[@]} -eq 0 ] && login_error "$(cat "$ERRFILE")"; then
    echo "NOTE: anonymous access hit a login/rate-limit wall; retrying once with --cookies-from-browser chrome" >&2
    COOKIE_ARGS=(--cookies-from-browser chrome)
    out="$(uvx yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} "$@" 2>"$ERRFILE")"; rc=$?
  fi
  if [ $rc -ne 0 ]; then cat "$ERRFILE" >&2; fi
  printf '%s' "$out"
  return $rc
}

# --- Step 1: metadata (this is where a login wall shows up first) -------------
echo "Fetching metadata (anonymous)..." >&2
JSON="$(run_ytdlp -J --no-warnings "$URL")"; rc=$?
LAST_ERR="$(cat "$ERRFILE")"   # read in the PARENT - run_ytdlp ran in a subshell
if [ $rc -ne 0 ] || [ -z "$JSON" ]; then
  # An image carousel/photo post has no video formats. That's not an error -
  # it means the caller should switch to the image path (fetch-images.sh).
  if grep -qiE 'no video formats' <<<"${LAST_ERR:-}"; then
    echo "RESULT: IMAGE_POST this is a photo/carousel, not a video. Use fetch-images.sh." >&2
    exit 4
  fi
  if login_error "${LAST_ERR:-}"; then
    echo "RESULT: LOGIN_REQUIRED even after --cookies-from-browser chrome. Stopping." >&2
    exit 2
  fi
  echo "RESULT: ERROR yt-dlp could not read this URL. See stderr above." >&2
  exit 3
fi

# --- Step 2: parse fields + build the destination folder ----------------------
# Stash the metadata in a file: `python3 - <<'PY'` reads the *program* from
# stdin via `-`, so a here-doc'd script can't also read JSON from stdin. Pass
# the file path as argv instead. This file also feeds --load-info-json below,
# so the download reuses this metadata with no second network round-trip.
JSONFILE="$(mktemp)"; printf '%s' "$JSON" > "$JSONFILE"   # cleaned by the EXIT trap set above

read -r AUTHOR DATE LIKES ID < <(python3 - "$JSONFILE" <<'PY'
import json, sys, re
data = json.load(open(sys.argv[1]))

def handle():
    # Prefer the real @handle. Instagram's uploader_id is often a numeric
    # account id, so only take it when it's not all digits. Otherwise recover
    # the handle from the profile URL or the "Video by <handle>" title.
    uid = (data.get("uploader_id") or "").lstrip("@")
    if uid and not uid.isdigit():
        return uid
    for url in (data.get("uploader_url"), data.get("channel_url")):
        if url:
            slug = url.rstrip("/").split("/")[-1].lstrip("@")
            if slug and not slug.isdigit():
                return slug
    m = re.search(r"[Vv]ideo by (\S+)", data.get("title") or "")
    if m:
        return m.group(1).lstrip("@")
    return data.get("uploader") or data.get("channel") or uid or "unknown"

author = re.sub(r"[^A-Za-z0-9._-]+", "-", handle()).strip("-._").lower() or "unknown"
ud = data.get("upload_date")  # YYYYMMDD
date = f"{ud[:4]}-{ud[4:6]}-{ud[6:8]}" if ud and len(ud) == 8 else ""
likes = data.get("like_count")
likes = str(likes) if isinstance(likes, int) else "unknown"
vid = data.get("id") or "reel"
print(author, date or "NODATE", likes, vid)
PY
)
[ "$DATE" = "NODATE" ] && DATE="$(date +%F)"

DEST="$INBOX/${AUTHOR}-${DATE}"
mkdir -p "$DEST"

# caption.txt (full description) + meta.json (author/likes/url/etc.)
python3 - "$DEST" "$URL" "$LIKES" "$JSONFILE" "$AUTHOR" <<'PY'
import json, sys, os
dest, url, likes, jsonfile, author = sys.argv[1:6]
data = json.load(open(jsonfile))
caption = data.get("description") or ""
with open(os.path.join(dest, "caption.txt"), "w") as f:
    f.write(caption.rstrip() + "\n")
meta = {
    "author": author,
    "author_display": data.get("uploader") or "",
    "url": url,
    "webpage_url": data.get("webpage_url") or url,
    "like_count": None if likes in ("unknown", "") else int(likes),
    "upload_date": data.get("upload_date"),
    "duration_sec": data.get("duration"),
    "title": data.get("title"),
    "id": data.get("id"),
}
with open(os.path.join(dest, "meta.json"), "w") as f:
    json.dump(meta, f, indent=2)
print("caption chars:", len(caption))
PY

# --- Step 3: download the video into the folder -------------------------------
echo "Downloading video..." >&2
# Reuse the metadata we already fetched (--load-info-json) to avoid a second
# network round-trip and a second chance at a login wall.
run_ytdlp --load-info-json "$JSONFILE" \
  -o "$DEST/video.%(ext)s" \
  --no-warnings --no-part >/dev/null; rc=$?
LAST_ERR="$(cat "$ERRFILE")"   # read in the PARENT

VIDEO="$(ls "$DEST"/video.* 2>/dev/null | head -1)"
if [ $rc -ne 0 ] || [ -z "$VIDEO" ]; then
  if login_error "${LAST_ERR:-}"; then
    echo "RESULT: LOGIN_REQUIRED on download even after cookie retry. Stopping." >&2
    exit 2
  fi
  echo "RESULT: ERROR download failed (metadata was fine). See stderr above." >&2
  exit 3
fi

# --- Done: emit a parseable RESULT block --------------------------------------
cat <<EOF
RESULT: OK
DEST=$DEST
VIDEO=$VIDEO
CAPTION=$DEST/caption.txt
META=$DEST/meta.json
AUTHOR=$AUTHOR
DATE=$DATE
LIKES=$LIKES
URL=$URL
EOF
exit 0
