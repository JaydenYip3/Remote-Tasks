---
name: animated-videos
description: Hand off an animated-video job to the remote Linux server. Use when the user wants an animated video (voiceover, silent, or character-driven). First asks the user in chat (one multiple-choice prompt for video type, format, model and effort, then voice model, script and scene direction as needed), then wakes the server over LAN, SSHes into /root/code/orchestration, starts a Claude agent there with the formatted request, waits for it to finish, then powers the server off. This agent only collects inputs and forwards the request; it does not make the video itself.
---

# Animated videos (remote hand-off)

Your only job is to collect the user's choices with the questions below,
format them, and forward them to an agent on the remote server. Do not write,
edit or improve the script, do not plan the animation, and do not do any of
the video work locally.

## 1. Collect the answers in chat

Ask everything in the chat with `AskUserQuestion`, so the user answers in
place and their answers come back as soon as they press submit. Don't send a
link or a file for this.

If the user already gave an answer when invoking the skill (for example they
pasted a script or said "vertical"), use it and leave that question out.

### Step 1: one prompt with the general options

Send **one** `AskUserQuestion` call with these four questions together:

| Header | Question | Options (first is the default) |
|---|---|---|
| Video type | What type of animated video? | Voiceover animation (a narrator reads your script) · Silent animation (music and sound effects, no narration) · Character-driven animation (WIP) |
| Format | Vertical or horizontal? | Vertical 9:16 (Recommended) (1080×1920, Shorts, Reels, TikTok) · Horizontal 16:9 (1920×1080, YouTube and desktop) |
| Model | Which model should the render agent use? | Opus (Recommended) (works on any plan) · Fable (most capable, needs Fable access) |
| Effort | How much effort? | High (Recommended) · Medium · Low · Xhigh. Say in the question that "max" can be typed in Other. |

Map the answers to these values: `type` = `voiceover` / `silent`,
`format` = `horizontal` / `vertical`, `model` = `opus` / `fable`,
`effort` = `low` / `medium` / `high` / `xhigh` / `max`. If a question comes
back unanswered, use the default.

- **Character-driven:** say it's still a work in progress and offer voiceover
  or silent. Stop there. Don't wake the server.
- **Fable:** remind the user that it only works if the account on the render
  machine has Fable access, and that the job stops before it starts if it
  doesn't.

### Step 2: voice model (voiceover only)

One `AskUserQuestion` call: "Which voice model?" with `v1 (Recommended)`,
`v2` and `v3` (energetic young American, YouTuber style). Default `v1`.

The voices are files in `/root/code/breeze_tts/voices/` on the render
machine: `v1` and `v2` are cloned voices (`.breeze`), `v3` is a designed voice
(`v3.txt`, a description plus `cfg`). When a voice is added there, add it here
and to the README.

### Animation style

`sci-fi-sitcom-thinline` is the only style for now, so don't ask. Mention it
in the summary. When a new style skill is added in
`~/code/videos/.claude/skills/`, add a Style question to step 1's prompt
(or step 2's, since step 1 already has four questions) and list the styles
here (see the README).

### Step 3: text, as plain messages

Free text doesn't fit the multiple-choice prompt, so ask in plain messages,
one at a time, and wait for each reply:

1. **Script (voiceover only, required):** "Send the script." Keep it exactly
   as given: wording, line breaks and punctuation. Don't continue without it.
2. **Scenes / direction / mood:** "Any specific scenes, direction or mood?
   (Describe it, or say 'skip' to let the server decide.)" Pass it along
   verbatim. For a silent video this is the content brief, so if the user
   skips it, ask once more for at least a topic or a one-line description.

## 2. Write the prompt file

Before writing, show the user a short summary of their choices (type, voice
model, model and effort, format, style, whether direction was given, and the first line of the script)
and send it without waiting. Only stop if the user corrects something.

Write the prompt to a file in your scratchpad directory (e.g.
`<scratchpad>/video-prompt.md`). Use the template for the chosen type and drop
any section whose value is skipped.

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

## Format
{format: "Horizontal, 16:9 (1920×1080)" or "Vertical, 9:16 (1080×1920)"}

## Animation style
{style}

## Scenes / direction / mood
{direction, verbatim}

## Script
{script, verbatim}
```

### Silent template

```
Create an animated video with no narration from the request below. Work in the current
directory and follow its CLAUDE.md / existing pipeline. Run the job to
completion without asking questions; if something is ambiguous, make a
reasonable choice and note it in your final summary. When done, print the
path(s) of the finished video file(s) and a short summary.

## Video type
Silent animation: no narration, so no TTS and no transcription. Skip the voice
steps of the pipeline and drive the timing from the animation itself. "Silent"
only means no voice: the video must still have a music track and sound effects
that fit the scenes. On-screen text is fine if it suits the style.

## Format
{format: "Horizontal, 16:9 (1920×1080)" or "Vertical, 9:16 (1080×1920)"}

## Animation style
{style}

## Scenes / direction / mood
{direction, verbatim}
```

## 3. Run the hand-off script

```bash
.claude/skills/animated-videos/scripts/remote-task.sh --model <model> --effort <effort> -f <scratchpad>/video-prompt.md
```

`--model` and `--effort` take the values from step 1. They're passed to the
remote `claude`, not written into the prompt.

Run it with `run_in_background: true` (renders can take a long time) and
wait for the completion notification rather than polling.

The script, in order:
1. Checks whether the server already answers SSH. If it does, it skips the
   wake-up and will **not** power it off at the end.
2. Otherwise sends a Wake-on-LAN packet to `$WOL_MAC` and polls SSH on
   `$REMOTE_USER@$REMOTE_HOST` until it answers (up to `$BOOT_TIMEOUT`s).
3. If the model is Fable, makes a one-line test call with Fable on the remote
   machine. If that fails, it prints `FABLE_UNAVAILABLE`, powers the server
   off if it woke it, and exits 4 without starting the job.
4. Runs `claude -p` in `$REMOTE_DIR` with the prompt on stdin. The remote agent
   handles everything from there, and its final output is printed.
5. Checks that a new `.mp4` was produced (exit 3 if not).
6. Powers the server off (`POWEROFF_AFTER=1`, the default), but only if this
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
- Exit 4 / `FABLE_UNAVAILABLE`: remind the user that the render machine's
  account doesn't seem to have Fable (show the last output lines, since a
  network error can look the same), and ask whether to run it with Opus
  instead. Don't switch models without asking.
