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
