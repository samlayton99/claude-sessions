#!/bin/bash
# Install claude-sessions
# Usage: curl -fsSL https://raw.githubusercontent.com/samlayton99/claude-sessions/main/install.sh | bash

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/samlayton99/claude-sessions/main"

SCRIPTS_DIR="$HOME/.claude/scripts"
COMMANDS_DIR="$HOME/.claude/commands"

echo "Installing claude-sessions..."

# Create directories
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$COMMANDS_DIR"

# Download files
curl -fsSL "$REPO_URL/scripts/sessions.sh" -o "$SCRIPTS_DIR/sessions.sh"
curl -fsSL "$REPO_URL/commands/sessions.md" -o "$COMMANDS_DIR/sessions.md"

# Make script executable
chmod +x "$SCRIPTS_DIR/sessions.sh"

# Auto-configure permissions so the script never prompts for approval
SETTINGS_FILE="$HOME/.claude/settings.json"
PERM_ENTRY="Bash(~/.claude/scripts/sessions.sh:*)"

python3 -c "
import json, os, sys

settings_file = sys.argv[1]
entry = sys.argv[2]

if os.path.exists(settings_file):
    with open(settings_file) as f:
        settings = json.load(f)
else:
    settings = {}

perms = settings.setdefault('permissions', {})
allow = perms.setdefault('allow', [])

if entry not in allow:
    allow.append(entry)
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print(f'  Added permission: {entry}')
else:
    print(f'  Permission already configured.')
" "$SETTINGS_FILE" "$PERM_ENTRY"

echo ""
echo "Installed successfully."
echo ""
echo "  Script:  $SCRIPTS_DIR/sessions.sh"
echo "  Command: $COMMANDS_DIR/sessions.md"
echo ""
echo "Usage inside Claude Code:"
echo "  /user:sessions                  — list all sessions"
echo "  /user:sessions --find \"auth\"    — find sessions by name"
echo "  /user:sessions --delete \"auth\"  — delete session by name"
echo "  /user:sessions --delete         — delete all unnamed sessions"
echo ""
echo "To uninstall:"
echo "  curl -fsSL $REPO_URL/uninstall.sh | bash"
