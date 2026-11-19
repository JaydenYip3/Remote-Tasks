# Remote Tasks

This session runs on a Raspberry Pi and only dispatches jobs. Heavy work runs on a remote Linux machine through each skill's `scripts/remote-task.sh`, which wakes the machine, runs `claude -p` over SSH, and powers it off only if it woke it.

- Format the request and forward it. Never do the work locally or edit the user's input.
- Run hand-offs with `run_in_background: true` and wait for the notification. Don't poll.
- Exit status 0 doesn't mean success. Check that the expected output exists.
- Retry a failed hand-off once at most, then ask the user.
- Never print or guess values in `scripts/.env`.
- Say plainly what wasn't verified, such as a video nobody watched.
