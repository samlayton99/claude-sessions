#!/bin/bash
# Uninstall claude-sessions

set -euo pipefail

SCRIPT="$HOME/.claude/scripts/sessions.sh"
COMMAND="$HOME/.claude/commands/sessions.md"

echo "Uninstalling claude-sessions..."

[ -f "$SCRIPT" ] && rm "$SCRIPT" && echo "  Removed: $SCRIPT"
[ -f "$COMMAND" ] && rm "$COMMAND" && echo "  Removed: $COMMAND"

# Remove permission entry from settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"
PERM_ENTRY="Bash(~/.claude/scripts/sessions.sh:*)"

if [ -f "$SETTINGS_FILE" ]; then
  python3 -c "
import json, sys

settings_file = sys.argv[1]
entry = sys.argv[2]

with open(settings_file) as f:
    settings = json.load(f)

allow = settings.get('permissions', {}).get('allow', [])
if entry in allow:
    allow.remove(entry)
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print(f'  Removed permission: {entry}')
else:
    print('  Permission entry not found (already clean).')
" "$SETTINGS_FILE" "$PERM_ENTRY"
fi

echo ""
echo "Uninstalled. Restart Claude Code or run /reload to clear the command."
