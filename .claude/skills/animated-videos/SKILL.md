---
name: animated-videos
description: Hand off an animated-video job to the remote Linux server. Use when the user wants an animated video (voiceover, silent, or character-driven). First sends the user an HTML form (video type, then script / voice model / animation style / scene direction as needed) and reads back the answers they paste, then wakes the server over LAN, SSHes into /root/code/orchestration, starts a Claude agent there with the formatted request, waits for it to finish, then powers the server off. This agent only collects inputs and forwards the request; it does not make the video itself.
---

# Animated videos (remote hand-off)

Your only job is to collect the user's choices with the form below,
format them, and forward them to an agent on the remote server. Do not write,
edit or improve the script, do not plan the animation, and do not do any of
the video work locally.

## 1. Collect the answers with the form

The questions live in one HTML form, [`form.html`](form.html), next to this
file. It shows only the questions that apply to the chosen video type, checks
required fields, and gives the user a `VIDEO_REQUEST {...}` JSON block to paste
back. You don't need to ask the questions one by one.

### Send the form

1. Publish `form.html` with the Artifact tool and give the user the link. If
   you already published it in this conversation, republish the same
   `file_path` instead of creating a new artifact. Don't change the file.
2. If the Artifact tool isn't available, send the file with `SendUserFile`.
3. If neither works, or the user says they'd rather answer in chat, use the
   [chat fallback](#chat-fallback) below.

Then ask the user to fill it in, press **Send**, and paste the result back. Wait
for the reply.

If the user already gave every answer when invoking the skill (for example
they pasted a script and said what they want), skip the form. If they gave some
answers, still send the form and tell them which of their answers you'll use.

If the user picks Fable, remind them in your reply that it only works if the
account on the render machine has Fable access, and that the job stops before
it starts if it doesn't.

### Read the pasted result

The user pastes a block like this:

```
VIDEO_REQUEST {
  "type": "voiceover",
  "script": "…",
  "voice_model": "v1",
  "model": "opus",
  "effort": "high",
  "format": "horizontal",
  "style": "sci-fi-sitcom-thinline",
  "direction": "skip"
}
```

| Field | Values | Shown for |
|---|---|---|
| `type` | `voiceover`, `silent` | always |
| `script` | text, verbatim | voiceover (required) |
| `voice_model` | `v1` (default), `v2` | voiceover |
| `model` | `opus` (default), `fable` | voiceover, silent |
| `effort` | `low`, `medium`, `high` (default), `xhigh`, `max` | voiceover, silent |
| `format` | `horizontal` (16:9, 1920×1080, default), `vertical` (9:16, 1080×1920) | voiceover, silent |
| `style` | `sci-fi-sitcom-thinline` (the only style for now) | voiceover, silent |
| `direction` | text, verbatim, or `skip` | voiceover (optional), silent (required) |

The styles must match the options in `form.html`. When a new style is added
in `~/code/videos/.claude/skills/`, update both files (see the README).

- Parse it as JSON. Use `script` and `direction` exactly as given, with
  their wording, line breaks and punctuation.
- If a field is missing, use the default: `v1` for `voice_model`,
  `opus` for `model`, `high` for `effort`, `horizontal` for `format`, `sci-fi-sitcom-thinline` for `style`, `skip` for `direction`.
- If `type` is `voiceover` and `script` is missing or empty, ask for the
  script. If `type` is `silent` and `direction` is `skip`, ask once for at
  least a topic or a one-line description.
- The form blocks character-driven videos. If one still comes through, say
  it's a work in progress and offer voiceover or silent. Don't wake the server.
- If the paste isn't valid JSON, ask the user to copy it again with the
  form's **Copy** button. Don't guess what it meant.

### Chat fallback

Ask the same questions one at a time. Use `AskUserQuestion` for multiple
choice and a plain message for free text:

1. **Video type:** Voiceover animation / Silent animation / Character-driven
   animation (WIP). Character-driven isn't built yet, so offer the other two
   and stop.
2. **Voiceover only:** the script (free text, required, verbatim), then the
   voice model: `v1 (Recommended)` / `v2`.
3. **Model:** Opus (Recommended) / Fable. If they pick Fable, remind them it
   needs Fable access on the render machine's account.
4. **Effort:** low / medium / high (Recommended) / xhigh / max. Offer four of
   these as options and let "Other" cover the fifth.
5. **Format:** Horizontal (16:9) (Recommended) / Vertical (9:16).
6. **Animation style:** `sci-fi-sitcom-thinline` is the only style for now,
   so don't ask. Tell the user it will be used.
7. **Scenes / direction / mood:** "Any specific scenes, direction or mood?
   (Describe it, or say 'skip' to let the server decide.)" Required for
   silent videos, so ask once more if it's skipped.

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

`--model` and `--effort` take the values from the form. They're passed to the
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
