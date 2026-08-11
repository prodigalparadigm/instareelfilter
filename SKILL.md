---
name: reel-gate
description: >-
  A decision gate for whether something worth saving - an Instagram reel, a
  video, an article, a screenshot of a prompt - should become a reusable Claude
  skill, or be rejected honestly. Use whenever the user is about to turn captured
  content into a skill, asks "should this be a skill", says "reel this" or "skill
  this", or is sitting on a pile of saved links they want to triage. Scans the
  user's existing skills for overlap, shows a short summary, and asks for one of
  three stamps before anything gets built. Zero dependencies: it is a judgment
  procedure, not a pipeline. Trigger even when the user does not say the word
  "skill" but clearly wants to decide if an idea is worth capturing.
---

# The Gate

Most saved content is never acted on. The folder fills up, nothing gets a
verdict, and the collection becomes a graveyard. This gate fixes that by forcing
one decision per item, before any building happens.

The rule is simple: the human is the judge, the machine is the clerk. You do the
scan and lay out the evidence. The person gives the verdict.

## The three stamps

Every candidate gets exactly one:

- ALREADY HAVE - we do this. Close the tab.
- STEAL ONE LINE - old tactic, one sentence worth keeping. Take the sentence, close the tab.
- GENUINELY NEW - rare. This one earns a build.

## When to run

The user has something they are considering turning into a skill and wants to
know if it is worth it: a reel or video they just watched, an article, a prompt
someone shared, or a backlog of saved links to triage one at a time.

## Step 1: scan for overlap

Read the name and description of every skill the user already has, so you can
judge overlap against what this candidate actually teaches - not against surface
keywords.

```bash
for f in ~/.claude/skills/*/SKILL.md; do
  echo "### $(basename "$(dirname "$f")")"
  sed -n '1,12p' "$f"
  echo
done
```

Judge by function. A candidate about "cold-brew ratios" and a skill about "coffee
tasting notes" both touch coffee but do not overlap in what they do.

## Step 2: present the evidence and ask for a stamp

Show the user this, then stop and wait. Keep the workflow summary to three lines,
and name any overlapping skill explicitly.

```
Candidate: <one line on what it teaches>
Workflow:  <line 1 - the core move>
           <line 2 - inputs, or when you would use it>
           <line 3 - output, or what you end up with>
Overlap:   <named existing skill and how it overlaps, or "none found">

Stamp it: ALREADY HAVE - STEAL ONE LINE - GENUINELY NEW
```

Do not pick the stamp yourself. Give your honest read if you have one, then let
the person decide.

## Step 3: act on the stamp

- ALREADY HAVE - stop. Build nothing. Log one line on why it was redundant, so
  the rejection is on the record and the same idea does not come back next month.

- STEAL ONE LINE - no new skill. Propose a small amendment to the named existing
  skill, usually one sentence or a bullet that captures the single good idea.
  Show it as a diff and apply only after the user says yes.

- GENUINELY NEW - proceed to build the skill. If you built it from someone
  else's content, record the source inside the new skill so its lineage stays
  traceable.

## Why this works

Filtering beats hoarding. A verdict, even a "no", is worth more than another
item added to a pile no one revisits. Most things are ALREADY HAVE. A few are
worth one stolen line. The rare one that is GENUINELY NEW is the only one that
earns the work of a build, and now you can tell which is which.
