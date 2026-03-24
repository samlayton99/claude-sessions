#!/bin/bash
# Claude Code Session Manager
# Manage sessions for the current project directory.
#
# Usage:
#   sessions.sh                        # list all sessions
#   sessions.sh --find "query"         # find sessions matching query
#   sessions.sh --delete "name"        # delete session by name (dry run)
#   sessions.sh --delete               # delete all unnamed sessions (dry run)
#   sessions.sh --delete "name" --yes  # actually delete session by name
#   sessions.sh --delete --yes         # actually delete all unnamed sessions

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve project directory
# ---------------------------------------------------------------------------

PROJ=$(echo "$PWD" | sed 's|/|-|g')
DIR="$HOME/.claude/projects/$PROJ"

if [ ! -d "$DIR" ]; then
  echo "No sessions found for project: $PWD"
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

get_title() {
  python3 -c "
import json, sys
title = ''
with open(sys.argv[1]) as f:
    for line in f:
        try:
            d = json.loads(line)
            if d.get('type') == 'custom-title':
                title = d['customTitle']
            if d.get('type') == 'agent-name':
                title = d['agentName']
        except:
            pass
print(title)
" "$1"
}

get_first_message() {
  python3 -c "
import json, sys
msg = ''
with open(sys.argv[1]) as f:
    for line in f:
        try:
            d = json.loads(line)
            if d.get('type') == 'user' and d.get('message'):
                content = d['message'].get('content', '')
                if isinstance(content, str):
                    msg = content
                elif isinstance(content, list):
                    for block in content:
                        if block.get('type') == 'text':
                            msg = block.get('text', '')
                            break
                break
        except:
            pass
if len(msg) > 80:
    msg = msg[:80] + '...'
print(msg)
" "$1"
}

get_message_count() {
  python3 -c "
import json, sys
count = 0
with open(sys.argv[1]) as f:
    for line in f:
        try:
            d = json.loads(line)
            if d.get('type') == 'user':
                count += 1
        except:
            pass
print(count)
" "$1"
}

format_size() {
  local bytes=$1
  if [ "$bytes" -lt 1024 ]; then
    echo "${bytes}B"
  elif [ "$bytes" -lt 1048576 ]; then
    echo "$(( bytes / 1024 ))K"
  else
    echo "$(echo "scale=1; $bytes / 1048576" | bc)M"
  fi
}

get_mod_date() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f "%Sm" -t "%Y-%m-%d" "$1"
  else
    stat -c "%y" "$1" | cut -d' ' -f1
  fi
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

MODE=""
TARGET=""
CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --find)
      MODE="find"
      TARGET="${2:-}"
      shift
      [ -n "$TARGET" ] && shift
      ;;
    --delete)
      MODE="delete"
      if [[ "${2:-}" != "" && "${2:-}" != "--yes" ]]; then
        TARGET="$2"
        shift
      fi
      shift
      ;;
    --yes)
      CONFIRM=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# MODE: list (default)
# ---------------------------------------------------------------------------

if [ -z "$MODE" ]; then
  echo "Sessions for: $PWD"
  echo ""

  count=0
  for f in "$DIR"/*.jsonl; do
    [ -f "$f" ] || continue

    sid=$(basename "$f" .jsonl)

    # Skip agent sessions
    [[ "$sid" == agent-* ]] && continue

    # Skip empty files
    [ ! -s "$f" ] && continue

    title=$(get_title "$f")
    first_msg=$(get_first_message "$f")
    msg_count=$(get_message_count "$f")
    mod_date=$(get_mod_date "$f")
    file_size=$(wc -c < "$f" | tr -d ' ')
    size_str=$(format_size "$file_size")

    if [ -n "$title" ]; then
      display_name="$title"
    else
      display_name="(unnamed)"
    fi

    echo "$display_name"
    echo "  $mod_date | $size_str | ${msg_count} msgs | $first_msg"
    echo ""
    count=$((count + 1))
  done

  if [ "$count" -eq 0 ]; then
    echo "No sessions found."
  else
    echo "Total: $count session(s)"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# MODE: find
# ---------------------------------------------------------------------------

if [ "$MODE" = "find" ]; then
  if [ -z "$TARGET" ]; then
    echo "Usage: sessions.sh --find \"query\""
    exit 1
  fi

  echo "Sessions matching: \"$TARGET\""
  echo ""

  query_lower=$(echo "$TARGET" | tr '[:upper:]' '[:lower:]')
  count=0

  for f in "$DIR"/*.jsonl; do
    [ -f "$f" ] || continue

    sid=$(basename "$f" .jsonl)
    [[ "$sid" == agent-* ]] && continue
    [ ! -s "$f" ] && continue

    title=$(get_title "$f")
    title_lower=$(echo "$title" | tr '[:upper:]' '[:lower:]')

    if [[ "$title_lower" == *"$query_lower"* ]]; then
      first_msg=$(get_first_message "$f")
      msg_count=$(get_message_count "$f")
      mod_date=$(get_mod_date "$f")
      file_size=$(wc -c < "$f" | tr -d ' ')
      size_str=$(format_size "$file_size")

      if [ -n "$title" ]; then
        display_name="$title"
      else
        display_name="(unnamed)"
      fi

      echo "$display_name"
      echo "  $mod_date | $size_str | ${msg_count} msgs | $first_msg"
      echo ""
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    echo "No sessions found matching \"$TARGET\"."
  else
    echo "Found: $count session(s)"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# MODE: delete
# ---------------------------------------------------------------------------

if [ "$MODE" = "delete" ]; then

  # --- Delete by name ---
  if [ -n "$TARGET" ]; then
    # Find matching sessions
    matches=()
    match_files=()

    for f in "$DIR"/*.jsonl; do
      [ -f "$f" ] || continue
      sid=$(basename "$f" .jsonl)
      [[ "$sid" == agent-* ]] && continue
      [ ! -s "$f" ] && continue

      title=$(get_title "$f")
      if [ "$title" = "$TARGET" ]; then
        matches+=("$sid")
        match_files+=("$f")
      fi
    done

    if [ ${#matches[@]} -eq 0 ]; then
      echo "No session found with name: \"$TARGET\""
      exit 1
    fi

    if [ "$CONFIRM" = true ]; then
      for i in "${!matches[@]}"; do
        rm "${match_files[$i]}"
        rm -rf "$DIR/${matches[$i]}/" 2>/dev/null
        echo "Deleted: ${matches[$i]}"
      done
      echo "Deleted ${#matches[@]} session(s)."
    else
      echo "The following session(s) will be deleted:"
      echo ""
      for i in "${!matches[@]}"; do
        f="${match_files[$i]}"
        first_msg=$(get_first_message "$f")
        mod_date=$(get_mod_date "$f")
        file_size=$(wc -c < "$f" | tr -d ' ')
        size_str=$(format_size "$file_size")
        echo "  $TARGET (${matches[$i]})"
        echo "    $mod_date | $size_str | $first_msg"
      done
      echo ""
      echo "AWAITING_CONFIRMATION"
    fi
    exit 0
  fi

  # --- Delete all unnamed ---
  unnamed=()
  unnamed_files=()

  for f in "$DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    sid=$(basename "$f" .jsonl)
    [[ "$sid" == agent-* ]] && continue
    [ ! -s "$f" ] && continue

    title=$(get_title "$f")
    if [ -z "$title" ]; then
      unnamed+=("$sid")
      unnamed_files+=("$f")
    fi
  done

  if [ ${#unnamed[@]} -eq 0 ]; then
    echo "No unnamed sessions found."
    exit 0
  fi

  if [ "$CONFIRM" = true ]; then
    for i in "${!unnamed[@]}"; do
      rm "${unnamed_files[$i]}"
      rm -rf "$DIR/${unnamed[$i]}/" 2>/dev/null
      echo "Deleted: ${unnamed[$i]}"
    done
    echo "Deleted ${#unnamed[@]} unnamed session(s)."
  else
    echo "The following unnamed session(s) will be deleted:"
    echo ""
    for i in "${!unnamed[@]}"; do
      f="${unnamed_files[$i]}"
      first_msg=$(get_first_message "$f")
      mod_date=$(get_mod_date "$f")
      file_size=$(wc -c < "$f" | tr -d ' ')
      size_str=$(format_size "$file_size")
      echo "  (unnamed) — ${unnamed[$i]}"
      echo "    $mod_date | $size_str | $first_msg"
    done
    echo ""
    echo "Total: ${#unnamed[@]} unnamed session(s)"
    echo ""
    echo "AWAITING_CONFIRMATION"
  fi
  exit 0
fi
