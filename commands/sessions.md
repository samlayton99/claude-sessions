Manage Claude Code sessions for the current project.

Run: `~/.claude/scripts/sessions.sh $ARGUMENTS`

## Behavior

**No arguments** → List all sessions. Format the output cleanly for the user. Include the available flags shown at the end of the output.

**--new "name"** → Create a new named session. After creation, tell the user to run `/resume` to switch to it.

**--find "query"** → Show matching sessions. Format the output cleanly.

**--delete "name"** → First run WITHOUT `--yes`. This is a dry run that shows what will be deleted. Show the list to the user and ask: "Delete these sessions?" If the user confirms, run again WITH `--yes` to perform the deletion.

**--delete** (no name) → Same two-step flow. First run without `--yes` to show all unnamed sessions that will be deleted. Ask the user to confirm. Then run with `--yes`.

## Important

- When the script outputs `AWAITING_CONFIRMATION`, you MUST ask the user to confirm before running with `--yes`.
- Never add `--yes` on the first run. Always show the dry run first.
- After deletion, report how many sessions were deleted.
