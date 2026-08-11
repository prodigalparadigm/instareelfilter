#!/usr/bin/env bash
# reel-to-skill - Part 2 - Transcribe (Apple Silicon, local)
# Runs Whisper locally via mlx-whisper (turbo model) through uvx.
#
# FIRST RUN DOWNLOADS ~2GB: uvx fetches mlx-whisper + its deps, and the
# turbo model weights (mlx-community/whisper-large-v3-turbo) are pulled from
# Hugging Face and cached under ~/.cache/huggingface. Do the first run on
# good wifi. Every run after that is offline/fast.
#
# Usage:   transcribe.sh <video-file | folder-containing-video.*>
# Output:  writes <folder>/transcript.txt next to the video and prints a
#          RESULT block including a SPEECH_VERDICT for the orchestrating skill.
#
# The verdict is a heuristic signal, not the final word: OK = looks like real
# speech; SUSPECT = likely music-only or nonsense repetition, in which case the
# skill should build from the caption instead and say so.
#
# Exit codes: 0 success (see SPEECH_VERDICT) - 3 usage/other error
set -uo pipefail

MODEL="mlx-community/whisper-large-v3-turbo"   # "turbo"

ARG="${1:-}"
if [ -z "$ARG" ]; then
  echo "RESULT: ERROR usage: transcribe.sh <video-file|folder>" >&2
  exit 3
fi

# Accept either a video file or a folder containing video.*
if [ -d "$ARG" ]; then
  VIDEO="$(ls "$ARG"/video.* 2>/dev/null | head -1)"
else
  VIDEO="$ARG"
fi
if [ -z "${VIDEO:-}" ] || [ ! -f "$VIDEO" ]; then
  echo "RESULT: ERROR no video file found at: $ARG" >&2
  exit 3
fi

DIR="$(cd "$(dirname "$VIDEO")" && pwd)"
BASE="$(basename "$VIDEO")"; STEM="${BASE%.*}"

# --- locate uvx ---------------------------------------------------------------
for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH
if ! command -v uvx >/dev/null 2>&1; then
  echo "RESULT: ERROR uvx not found. Install with: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 3
fi

# --- pre-check: does the video even have an audio stream? ---------------------
# Silent reels (text/visual montages) download as video-only. Without this check
# mlx-whisper/ffmpeg dies with a cryptic "Output file does not contain any
# stream". Detect it up front and signal a clean caption fallback instead.
if command -v ffprobe >/dev/null 2>&1; then
  HAS_AUDIO="$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$VIDEO" 2>/dev/null)"
  if [ -z "$HAS_AUDIO" ]; then
    # No speech to transcribe. Sample frames so the gate still has something to
    # read (text/visual reels put their whole point on screen), then fall back
    # to the caption. More signal means a better-calibrated verdict.
    echo "No audio track; sampling frames for the gate to read..." >&2
    ffmpeg -v error -i "$VIDEO" -vf fps=1 -frames:v 12 "$DIR/frame-%02d.jpg" 2>/dev/null || true
    FRAMES="$(ls "$DIR"/frame-*.jpg 2>/dev/null | sort)"
    echo "SPEECH_VERDICT: NO_AUDIO - no audio track; read the sampled frames and the caption" >&2
    echo "RESULT: NO_AUDIO"
    echo "VIDEO=$VIDEO"
    [ -n "$FRAMES" ] && printf '%s\n' "$FRAMES" | sed 's/^/FRAME=/'
    exit 0
  fi
fi

# --- run mlx-whisper (documented CLI: positional audio + --model/--output-*) --
# mlx_whisper decodes the video via ffmpeg, so a raw .mp4 is fine as input.
# It writes <STEM>.txt into --output-dir; we normalize that to transcript.txt.
echo "Transcribing with $MODEL (first run downloads ~2GB)..." >&2
uvx --from mlx-whisper mlx_whisper "$VIDEO" \
  --model "$MODEL" \
  --output-dir "$DIR" \
  --output-format txt \
  --verbose False 2>&1 | tail -3 >&2
rc=${PIPESTATUS[0]}

RAW="$DIR/$STEM.txt"
TRANSCRIPT="$DIR/transcript.txt"
if [ $rc -ne 0 ] || [ ! -f "$RAW" ]; then
  echo "RESULT: ERROR transcription failed (mlx-whisper). See stderr above." >&2
  exit 3
fi
[ "$RAW" != "$TRANSCRIPT" ] && mv -f "$RAW" "$TRANSCRIPT"

# --- speech-vs-noise heuristic ------------------------------------------------
# Flags the common Whisper-on-music failure modes: empty output, a single
# phrase repeated, musical-note / [Music] tags, or a very low unique-word ratio.
python3 - "$TRANSCRIPT" <<'PY'
import re, sys, collections
text = open(sys.argv[1], encoding="utf-8", errors="replace").read().strip()
words = re.findall(r"[A-Za-z']+", text.lower())
n = len(words)
uniq = len(set(words))
ratio = uniq / n if n else 0.0
lines = [l.strip() for l in text.splitlines() if l.strip()]
top_line_frac = 0.0
if lines:
    c = collections.Counter(lines)
    top_line_frac = c.most_common(1)[0][1] / len(lines)
music_tags = len(re.findall(r"\[(?:music|applause|silence)\]|[♪♫♩♨]", text, re.I))
tag_ratio = music_tags / max(len(lines), 1)

reasons = []
if n < 5:
    reasons.append(f"only {n} words")
if n >= 20 and ratio < 0.25:
    reasons.append(f"low variety (unique-word ratio {ratio:.2f})")
if top_line_frac >= 0.5 and len(lines) >= 4:
    reasons.append(f"one line repeats {top_line_frac:.0%} of the transcript")
if tag_ratio >= 0.5 and len(lines) >= 2:
    reasons.append("mostly music/non-speech tags")

verdict = "SUSPECT" if reasons else "OK"
print(f"WORDS={n} UNIQUE={uniq} RATIO={ratio:.2f} TOP_LINE_FRAC={top_line_frac:.2f} MUSIC_TAGS={music_tags}")
print(f"SPEECH_VERDICT: {verdict}" + (" - " + "; ".join(reasons) if reasons else ""))
PY

cat <<EOF
RESULT: OK
TRANSCRIPT=$TRANSCRIPT
VIDEO=$VIDEO
MODEL=$MODEL
EOF
exit 0
