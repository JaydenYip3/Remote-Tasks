# Remote Tasks

A Raspberry Pi runs a background [Claude Code](https://claude.com/claude-code) session that you control through Remote Control. The Pi has little compute, so it forwards heavy jobs to a stronger Linux machine, wakes it over the LAN, and powers it off when the job is done.

```
You (Remote Control) → Raspberry Pi → Wake-on-LAN + SSH → Render machine
```

Each job type is a skill in `.claude/skills/`. Start one with `/<skill-name>` and its inputs.

## Skills

### `animated-videos`

Makes a short animated video. Run `/animated-videos` and Claude asks you everything in the chat. The general options come first, as one multiple-choice prompt that goes through when you press submit. The text (script, direction) comes last, as plain messages:

```
1. One prompt: video type · format (vertical, the default | horizontal) · model (Opus | Fable) · effort (low to max)
   └─ Character-driven → WIP, not implemented yet
2. Voiceover only: voice model (v1 | v2)
3. Text: script (voiceover only) → scenes / direction / mood (required for silent)
```

The animation style is `sci-fi-sitcom-thinline`, the only one for now, so it isn't asked.

For voiceover videos, the render machine narrates the script with the Breeze TTS model (8-bit quantized), transcribes it, then animates and renders it in Remotion. Silent videos skip the voice steps but still get music and sound effects. You get the `.mp4` path back when it's done.

The model and effort (low to max) are passed to `claude` on the render machine as `--model` and `--effort`. If you pick Fable and that machine's account can't use it, the job stops before it starts and Claude reminds you, so you can rerun it with Opus.

#### Adding a new animation style

The skill only knows the styles listed in it. Right now that's `sci-fi-sitcom-thinline`. Whenever you add a new style skill in `~/code/videos/.claude/skills/`, update [`SKILL.md`](.claude/skills/animated-videos/SKILL.md) too:

1. Add the style, by its folder name, to the **Animation style** section.
2. Once there's more than one style, add a Style question to the voice-model prompt (step 2). Step 1's prompt is already full at four questions, which is the most one prompt can hold.
3. If the new style should be the default, list it first and mark it (Recommended).

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

