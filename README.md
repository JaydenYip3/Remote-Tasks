# Remote Tasks

A Raspberry Pi runs a background [Claude Code](https://claude.com/claude-code) session that you control through Remote Control. The Pi has little compute, so it forwards heavy jobs to a stronger Linux machine, wakes it over the LAN, and powers it off when the job is done.

```
You (Remote Control) → Raspberry Pi → Wake-on-LAN + SSH → Render machine
```

Each job type is a skill in `.claude/skills/`. Start one with `/<skill-name>` and its inputs.

## Skills

### `animated-videos`

Makes a short animated video. Run `/animated-videos` and answer a few questions before anything is sent to the render machine:

```
What type of video?
├─ Voiceover animation  → script → voice model (v1 | v2) → animation style → scenes / direction / mood
├─ Silent animation     → animation style → scenes / direction / mood
└─ Character-driven     → WIP, not implemented yet
```

For voiceover videos, the render machine narrates the script with the Breeze TTS model (8-bit quantized), transcribes it, then animates and renders it in Remotion. Silent videos skip the voice steps. You get the `.mp4` path back when it's done.

## Setup

Copy `scripts/.env.example` to `scripts/.env` in each skill and fill in the remote machine's MAC address, host, user and working directory.

> Keep `.env` out of git.

## Why?

- **Simple interface for repetitive work.** Routine jobs, like making a video, become one command from your phone.
- **Flexible pipelines.** These workflows usually depend on many tools that break easily. Using an LLM to orchestrate them lets the pipeline adapt, so you don't have to hard-code every step.

## Examples

### Video

**Input:**

![Input example](https://github.com/user-attachments/assets/10c6a337-665c-4130-84b9-765601d7a3df)

**Output (compressed):**

https://github.com/user-attachments/assets/3a9134a9-2505-49c1-b23c-95f493a12758

## More automation examples

_Add more examples here._

