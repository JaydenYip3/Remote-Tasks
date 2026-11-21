---
name: animated-videos
description: Hand off an animated-video job to the remote Linux server. Use when the user wants an animated video (voiceover, silent, or character-driven). First walks the user through a short decision tree of questions (video type, then script / voice model / animation style / scene direction as needed), then wakes the server over LAN, SSHes into /root/code/orchestration, starts a Claude agent there with the formatted request, waits for it to finish, then powers the server off. This agent only collects inputs and forwards the request; it does not make the video itself.
---

# Animated videos (remote hand-off)

Your only job is to collect the user's choices through the decision tree below,
format them, and forward them to an agent on the remote server. Do not write,
edit or improve the script, do not plan the animation, and do not do any of
the video work locally.

## 1. Decision tree

Ask the questions **one step at a time**, in the order below. Use
`AskUserQuestion` for multiple-choice steps. For free-text steps (script,
direction), ask in a plain message and wait for the reply.

If the user already gave an answer when invoking the skill (e.g. they pasted a
script or named a style), use it and skip that question. Don't ask again.

### Step 1: Video type (multiple choice)

Ask: "What type of animated video?"

| Option | Description |
|---|---|
| Voiceover animation | A narrator reads your script over the animation |
| Silent animation | Animation only, no narration |
| Character-driven animation | Characters speak on screen (WIP) |

Then follow the matching branch.

### Branch A: Voiceover animation

1. **Script (free text, required).** Ask the user to send the script. Keep it
   exactly as given (wording, line breaks, punctuation). Do not continue
   without it.
2. **Voice model (multiple choice).** Options: `v1 (Recommended)` (the default)
   and `v2`. If the user skips this question, use `v1`.
3. **Animation style.** Follow the [Animation style](#animation-style) step.
4. **Scenes / direction / mood.** Follow the
   [Scenes / direction / mood](#scenes--direction--mood) step.

### Branch B: Silent animation

1. **Animation style.** Follow the [Animation style](#animation-style) step.
2. **Scenes / direction / mood.** Follow the
   [Scenes / direction / mood](#scenes--direction--mood) step. For a silent
   video this is the main content brief, so if the user skips it, ask once
   more for at least a topic or a one-line description. A silent video needs
   something to animate.

### Branch C: Character-driven animation (WIP)

Not implemented yet. Tell the user that character-driven videos are still a
work in progress, and offer voiceover or silent instead. Stop here. Do not
wake the server.

### Animation style

Ask with `AskUserQuestion` (multiple choice). The user can also type their own
style through "Other".

| Option | Description |
|---|---|
| Server decides (Recommended) | Let the remote agent pick a style that fits |
| Flat motion graphics | Clean 2D shapes, icons and smooth transitions |
| Kinetic typography | Animated text is the main visual |
| Hand-drawn / sketch | Whiteboard or doodle look |

### Scenes / direction / mood

Ask in a plain message: "Any specific scenes, direction or mood? (Describe it,
or say 'skip' to let the server decide.)" Pass along whatever the user writes,
verbatim.

## 2. Write the prompt file

Before writing, show the user a short summary of their choices (type, voice
model, style, whether direction was given, and the first line of the script)
and send it without waiting. Only stop if the user corrects something.

Write the prompt to a file in your scratchpad directory (e.g.
`<scratchpad>/video-prompt.md`). Use the template for the chosen type and drop
any section whose value is "server decides" or skipped.

### Voiceover template

```
Create a voiceover animated video from the request below. Work in the current
directory and follow its CLAUDE.md / existing pipeline. Run the job to
completion without asking questions; if something is ambiguous, make a
reasonable choice and note it in your final summary. When done, print the
path(s) of the finished video file(s) and a short summary.

## Video type
Voiceover animation: narrate the script with TTS and animate to it.

## Voice model
{voice model}

## Animation style
{style}

## Scenes / direction / mood
{direction, verbatim}

## Script
{script, verbatim}
```

### Silent template

```
Create a silent animated video from the request below. Work in the current
directory and follow its CLAUDE.md / existing pipeline. Run the job to
completion without asking questions; if something is ambiguous, make a
reasonable choice and note it in your final summary. When done, print the
path(s) of the finished video file(s) and a short summary.

## Video type
Silent animation: no narration, no TTS and no transcription. Skip the voice
steps of the pipeline and drive the timing from the animation itself. On-screen
text is fine if it suits the style.

## Animation style
{style}

## Scenes / direction / mood
{direction, verbatim}
```

## 3. Run the hand-off script

```bash
.claude/skills/animated-videos/scripts/remote-task.sh -f <scratchpad>/video-prompt.md
```

Run it with `run_in_background: true` (renders can take a long time) and
wait for the completion notification rather than polling.

The script, in order:
1. Checks whether the server already answers SSH. If it does, it skips the
   wake-up and will **not** power it off at the end.
2. Otherwise sends a Wake-on-LAN packet to `$WOL_MAC` and polls SSH on
   `$REMOTE_USER@$REMOTE_HOST` until it answers (up to `$BOOT_TIMEOUT`s).
3. Runs `claude -p` in `$REMOTE_DIR` with the prompt on stdin. The remote agent
   handles everything from there, and its final output is printed.
4. Checks that a new `.mp4` was produced (exit 3 if not).
5. Powers the server off (`POWEROFF_AFTER=1`, the default), but only if this
   run woke it up.

Config lives in environment variables or `scripts/.env` (see
`scripts/.env.example`). If the script fails because `WOL_MAC` or `REMOTE_HOST`
is unset, tell the user to fill in `scripts/.env`. Never guess a MAC or IP.

## 4. Report back

- On success: relay the remote agent's final summary and the video path(s).
  Say that nobody has watched the video yet.
- On failure: say which step failed (wake / SSH timeout / Claude exit code /
  no video produced) and show the relevant output lines. Do not retry more
  than once without asking.
