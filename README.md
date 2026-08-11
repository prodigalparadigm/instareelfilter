# The Filter

A gate for turning saved reels into skills, or rejecting them honestly. If you
never install anything, this is the product. Every reel gets exactly one stamp:

- ALREADY HAVE - we do this. Close the tab.
- STEAL ONE LINE - old tactic, one sentence worth keeping. Take the sentence, close the tab.
- GENUINELY NEW - rare. This one earns a build.

Most saved content dies in a folder no one reopens. This is the opposite of that:
every reel gets one verdict, out loud, before anyone builds anything. The rest of
this page is how it runs.

## The practice

Filtering beats hoarding. A saved-reels folder feels like progress and delivers
none, because nothing in it ever gets a decision. A verdict, even a "no", is worth
more than one more item on the pile.

The division of labor is fixed: the human is the judge, the machine is the clerk.
The clerk fetches the reel, pulls the words off it, scans what you already have,
and lays the evidence out in three lines. The judge reads it and stamps it. The
machine never decides what is worth keeping. You do.

Most reels are ALREADY HAVE. Some are worth one stolen line. The rare one that is
GENUINELY NEW is the only one that earns a build, and the gate is what tells them
apart.

## Install the gate as a skill

The gate is a judgment procedure with zero dependencies. No downloads, no models,
no network. It reads the skills you already have and walks you through the three
stamps.

Drop [`SKILL.md`](SKILL.md) into `~/.claude/skills/reel-gate/` and it is live in
your next session. That is the entire install. Everything below is optional.

## Annex: the pipeline

Optional automation for people who want the clerk to do the fetching. It does one
reel at a time and hands the result to the gate. It never gives a verdict.

What it automates:

    fetch reel  ->  transcribe  ->  present for the gate

Real costs:

- `yt-dlp` for fetching, `gallery-dl` for image posts, both run on demand through `uvx` so nothing installs globally.
- `ffmpeg` for audio and frame handling.
- Whisper for local transcription. The first run downloads the model, about 2 GB, one time. Every run after is offline and fast.
- Written for macOS and compatible with the system bash 3.2. No newer shell required.

Scripts are in [`scripts/`](scripts/). The pipeline writes its working files to
`~/reel-to-skill/` and deletes the media once the words are out. Nothing produced
from someone else's reel is meant to be kept or committed.

## Input coverage, honestly

Not every reel gives the same signal, and the gate says so:

- Audio reels - a local Whisper transcript.
- Silent reels - sampled video frames plus the caption.
- Carousels and stills - the caption, plus the slides read directly when the substance is on them.

Calibration: thinner input still gets an honest verdict, at lower confidence. The
gate would rather tell you it is 60 percent sure than pretend a caption was a
transcript.

## Receipts

The maiden meals: the first reels run through the gate, anonymized. Creator handles
and links are removed on purpose. No personal names anywhere.

    date        stamp          what the reel taught                          outcome
    2026-08-09  ALREADY HAVE   the .claude folder is more than one file      built-in knowledge, no build
    2026-08-10  ALREADY HAVE   five plugins to install                       recommendation list, no build
    2026-08-10  ALREADY HAVE   five repos for learning to code               curated list, no build (silent reel, judged on caption)
    2026-08-10  GENUINELY NEW  a five-step premortem for stress-testing plans  built a skill
    2026-08-10  GENUINELY NEW  hiding payloads in AI model weights           built a defensive skill

Two builds, three honest rejections, zero graveyard. The rejections are the point
as much as the builds: the gate earns its keep by saying "no" quickly and on the
record.

## Credit

Scaffold adapted from the Jens guide.

Built by Kathleen Bartin, Prodigal Paradigm, with Claude.
