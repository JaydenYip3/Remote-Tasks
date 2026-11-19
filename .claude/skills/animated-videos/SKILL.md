---
name: animated-videos
description: Hand off an animated-video job to the remote Linux server. Use when the user sends a script (optionally a voice model, default v1, and an animation direction) for an animated video. Wakes the server over LAN, SSHes into /root/code/orchestration, starts a Claude agent there with the formatted request, waits for it to finish, then powers the server off. This agent only formats and forwards the request; it does not make the video itself.
---

# Animated videos (remote hand-off)

Your only job is to format the user's request and forward it to an agent on the
remote server. Do not write, edit or improve the script, do not plan the
animation, and do not do any of the video work locally.

## 1. Collect the input

The user sends:

```
Script: {script text}
Voice Model [optional, default v1]: {v1, v2, ...}
Animation Direction [optional]: {description}
```

- **Script** is required. If it is missing, ask for it before doing anything else.
- **Voice Model** defaults to `v1` when not given.
- **Animation Direction** is optional. If absent, leave it out of the prompt —
  the remote agent decides.
- Keep the script text exactly as given (wording, line breaks, punctuation).

## 2. Write the prompt file

Write the prompt to a file in your scratchpad directory (e.g.
`<scratchpad>/video-prompt.md`) in this format:

```
Create an animated video from the request below. Work in the current
directory and follow its CLAUDE.md / existing pipeline. Run the job to
completion without asking questions; if something is ambiguous, make a
reasonable choice and note it in your final summary. When done, print the
path(s) of the finished video file(s) and a short summary.

## Voice model
{voice model(s)}

## Animation direction
{direction — omit this whole section if none was given}

## Script
{script, verbatim}
```

## 3. Run the hand-off script

```bash
.claude/skills/animated-videos/scripts/remote-task.sh -f <scratchpad>/video-prompt.md
```

Run it with `run_in_background: true` — renders can take a long time — and
wait for the completion notification rather than polling.

The script, in order:
1. Checks whether the server already answers SSH. If it does, it skips the
   wake-up and will **not** power it off at the end.
2. Otherwise sends a Wake-on-LAN packet to `$WOL_MAC` and polls SSH on
   `$REMOTE_USER@$REMOTE_HOST` until it answers (up to `$BOOT_TIMEOUT`s).
3. Runs `claude -p` in `$REMOTE_DIR` with the prompt on stdin; the remote agent
   handles everything from there and its final output is printed.
4. Powers the server off (`POWEROFF_AFTER=1`, the default), but only if this
   run woke it up.

Config lives in environment variables or `scripts/.env` (see
`scripts/.env.example`). If the script fails because `WOL_MAC` or `REMOTE_HOST`
is unset, tell the user to fill in `scripts/.env` — never guess a MAC or IP.

## 4. Report back

- On success: relay the remote agent's final summary and the video path(s).
- On failure: say which step failed (wake / SSH timeout / Claude exit code) and
  show the relevant output lines. Do not retry more than once without asking.
