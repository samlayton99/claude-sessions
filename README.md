# claude-sessions

A simple session manager for Claude Code. List, search, and delete sessions directly from inside Claude Code using a slash command.

Addresses [anthropics/claude-code#13514](https://github.com/anthropics/claude-code/issues/13514) — there is currently no built-in way to delete sessions in Claude Code.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/samlayton99/claude-sessions/main/install.sh | bash
```

That's it. Two files get placed into `~/.claude/`:

| File | Location |
|------|----------|
| Script | `~/.claude/scripts/sessions.sh` |
| Command | `~/.claude/commands/sessions.md` |

## Usage

Inside Claude Code, type:

```
/sessions
```

List all sessions for the current project.

```
/sessions --find "auth"
```

Find sessions whose title matches "auth".

```
/sessions --delete "auth-system"
```

Delete a session by name. Claude will show you what will be deleted and ask for confirmation before proceeding.

```
/sessions --delete
```

Delete **all unnamed sessions** in the current project. Same confirmation flow — Claude shows the list first, then asks before deleting.

## How It Works

- Sessions live in `~/.claude/projects/`. Each project directory contains `.jsonl` files — one per session.
- The script scans the project directory matching your current working directory.
- Titles come from `/rename` entries (`custom-title`) or agent names in the session file.
- Deletions are two-step: the script does a dry run first, and Claude asks you to confirm before actually deleting anything.
- No dependencies beyond `bash` and `python3` (both already on your machine if you're running Claude Code).

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/samlayton99/claude-sessions/main/uninstall.sh | bash
```

## Manual Install

If you prefer not to pipe curl to bash:

```bash
git clone https://github.com/samlayton99/claude-sessions.git
cp claude-sessions/scripts/sessions.sh ~/.claude/scripts/sessions.sh
cp claude-sessions/commands/sessions.md ~/.claude/commands/sessions.md
chmod +x ~/.claude/scripts/sessions.sh
```

## License

MIT
