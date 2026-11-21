#!/usr/bin/env bash
# Wake a remote PC over LAN, wait for SSH, then run a Claude task on it.
#
# Usage:
#   remote-task.sh "prompt text"          # prompt as argument
#   remote-task.sh < prompt.txt           # prompt on stdin
#   remote-task.sh -f prompt.txt          # prompt from file
#   remote-task.sh --model fable --effort high -f prompt.txt
#
# Options (before the prompt):
#   --model  opus | fable                    model for the remote claude
#   --effort low | medium | high | xhigh | max
#
# With --model fable, a one-line test call runs first. If the remote account
# can't use Fable, the script stops with exit 4 before starting the job.
#
# Config comes from environment variables. If a .env file sits next to this
# script, it is loaded first (real environment values still win).
#
#   WOL_MAC          (required) MAC address of the remote PC, e.g. aa:bb:cc:dd:ee:ff
#   REMOTE_HOST      (required) hostname or IP of the remote PC
#   REMOTE_USER      ssh user                    (default: root)
#   REMOTE_DIR       working directory on remote (default: /root/code/orchestration)
#   WOL_BROADCAST    broadcast address for WoL   (default: 255.255.255.255)
#   WOL_PORT         WoL UDP port                (default: 9)
#   BOOT_TIMEOUT     seconds to wait for SSH     (default: 300)
#   CLAUDE_ARGS      extra args for remote claude (default: --dangerously-skip-permissions)
#   POWEROFF_AFTER   1 = power the PC off when done, 0 = leave it on (default: 1)
#   REQUIRE_VIDEO    1 = exit 3 if no new .mp4 appears on the remote (default: 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  # Load .env without overriding variables already set in the environment.
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    key="${key// /}"
    val="${val%\"}"; val="${val#\"}"
    [[ -z "${!key:-}" ]] && export "$key=$val"
  done < "$SCRIPT_DIR/.env"
fi

: "${WOL_MAC:?WOL_MAC is not set (MAC address of the remote PC)}"
: "${REMOTE_HOST:?REMOTE_HOST is not set (hostname or IP of the remote PC)}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_DIR="${REMOTE_DIR:-/root/code/orchestration}"
WOL_BROADCAST="${WOL_BROADCAST:-255.255.255.255}"
WOL_PORT="${WOL_PORT:-9}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
CLAUDE_ARGS="${CLAUDE_ARGS:---dangerously-skip-permissions}"
POWEROFF_AFTER="${POWEROFF_AFTER:-1}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# ---- read options -----------------------------------------------------------
MODEL=""; EFFORT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)  MODEL="${2:?--model needs a value}"; shift 2 ;;
    --effort) EFFORT="${2:?--effort needs a value}"; shift 2 ;;
    *) break ;;
  esac
done
# Whitelist values: they end up inside a remote shell command.
case "$MODEL" in ""|opus|fable) ;; *) echo "Unknown --model: $MODEL (use opus or fable)" >&2; exit 2 ;; esac
case "$EFFORT" in ""|low|medium|high|xhigh|max) ;; *) echo "Unknown --effort: $EFFORT" >&2; exit 2 ;; esac
[[ -n "$MODEL" ]] && CLAUDE_ARGS="$CLAUDE_ARGS --model $MODEL"
[[ -n "$EFFORT" ]] && CLAUDE_ARGS="$CLAUDE_ARGS --effort $EFFORT"

# ---- read the prompt --------------------------------------------------------
if [[ "${1:-}" == "-f" ]]; then
  PROMPT="$(cat "${2:?-f needs a file path}")"
elif [[ $# -gt 0 ]]; then
  PROMPT="$*"
elif [[ ! -t 0 ]]; then
  PROMPT="$(cat)"
else
  echo "No prompt given. Pass it as an argument, with -f FILE, or on stdin." >&2
  exit 2
fi
[[ -n "${PROMPT//[[:space:]]/}" ]] || { echo "Prompt is empty." >&2; exit 2; }

TARGET="$REMOTE_USER@$REMOTE_HOST"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5
          -o ServerAliveInterval=30 -o ServerAliveCountMax=6)

# ---- 1. already on? ---------------------------------------------------------
# If the PC already answers SSH, skip the wake-up and leave it on afterwards.
WAS_ON=0
if ssh "${SSH_OPTS[@]}" "$TARGET" true 2>/dev/null; then
  WAS_ON=1
  log "$REMOTE_HOST is already on; skipping Wake-on-LAN and will not power it off"
fi

if [[ "$WAS_ON" == "0" ]]; then
# ---- 2. wake on lan ---------------------------------------------------------
log "Sending Wake-on-LAN packet to $WOL_MAC via $WOL_BROADCAST:$WOL_PORT"
python3 - "$WOL_MAC" "$WOL_BROADCAST" "$WOL_PORT" <<'PY'
import socket, sys
mac, bcast, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
hexmac = mac.replace(":", "").replace("-", "").replace(".", "")
if len(hexmac) != 12:
    sys.exit(f"Invalid MAC address: {mac}")
packet = b"\xff" * 6 + bytes.fromhex(hexmac) * 16
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    for _ in range(3):
        s.sendto(packet, (bcast, port))
PY

# ---- 3. wait for ssh --------------------------------------------------------
log "Waiting up to ${BOOT_TIMEOUT}s for SSH on $TARGET"
deadline=$((SECONDS + BOOT_TIMEOUT))
until ssh "${SSH_OPTS[@]}" "$TARGET" true 2>/dev/null; do
  if (( SECONDS >= deadline )); then
    log "Timed out waiting for SSH on $TARGET"
    exit 1
  fi
  sleep 5
done
log "SSH is up"
fi

# ---- 3b. check fable access --------------------------------------------------
# A tiny test call, so a missing Fable plan fails here instead of mid-job.
if [[ "$MODEL" == "fable" ]]; then
  log "Checking that the remote account can use Fable"
  set +e
  check="$(ssh "${SSH_OPTS[@]}" "$TARGET" \
    "bash -lc 'cd $(printf '%q' "$REMOTE_DIR") && timeout 180 claude -p --model fable --output-format json \"Reply with only: OK\"'" 2>&1)"
  check_status=$?
  set -e
  if [[ "$check_status" != "0" || "$check" == *'"is_error":true'* ]]; then
    log "FABLE_UNAVAILABLE: the remote claude could not run Fable (status $check_status). Job not started."
    printf '%s\n' "$check" | tail -n 5 >&2
    if [[ "$POWEROFF_AFTER" == "1" && "$WAS_ON" == "0" ]]; then
      log "Powering off $REMOTE_HOST"
      ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl poweroff || poweroff" 2>/dev/null || true
    fi
    exit 4
  fi
  log "Fable is available"
fi

# ---- 4. run claude in the remote dir ---------------------------------------
# The prompt goes over stdin so no quoting/escaping issues with its content.
# `bash -lc` gives a login shell so claude is on PATH.
log "Starting Claude in $REMOTE_DIR"
# CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0: in print mode claude otherwise kills
# background subagents (e.g. the Remotion render) 10 min after its last turn.
MARKER="/tmp/remote-task-start.$$"
set +e
printf '%s' "$PROMPT" | ssh "${SSH_OPTS[@]}" "$TARGET" \
  "touch $MARKER && bash -lc 'cd $(printf '%q' "$REMOTE_DIR") && CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 claude -p $CLAUDE_ARGS'"
status=$?
set -e
log "Claude exited with status $status"

# ---- 4b. verify a video was actually produced -------------------------------
# Exit status 0 is not proof: a killed subagent still exits 0.
if [[ "$status" == "0" && "${REQUIRE_VIDEO:-1}" == "1" ]]; then
  videos="$(ssh "${SSH_OPTS[@]}" "$TARGET" \
    "find $(printf '%q' "$REMOTE_DIR") -name node_modules -prune -o -name '*.mp4' -newer $MARKER -print; rm -f $MARKER" 2>/dev/null || true)"
  if [[ -z "$videos" ]]; then
    log "ERROR: Claude exited 0 but no .mp4 newer than the job start was found in $REMOTE_DIR"
    status=3
  else
    log "Video(s) produced:"; printf '%s\n' "$videos" >&2
  fi
fi

# ---- 5. power off -----------------------------------------------------------
# Only power off if we were the ones who woke it up.
if [[ "$POWEROFF_AFTER" == "1" && "$WAS_ON" == "0" ]]; then
  log "Powering off $REMOTE_HOST"
  ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl poweroff || poweroff" 2>/dev/null || true
fi

exit "$status"
