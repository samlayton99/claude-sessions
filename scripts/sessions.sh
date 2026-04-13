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
#   sessions.sh --new "name"           # create a new named session

set -euo pipefail

PROJ=$(echo "$PWD" | sed 's|\.|-|g' | sed 's|/|-|g')
DIR="$HOME/.claude/projects/$PROJ"

if [ ! -d "$DIR" ]; then
  echo "No sessions found for project: $PWD"
  exit 1
fi

# Parse arguments in bash, pass as positional args to python
MODE="list"
TARGET=""
CONFIRM="false"

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
    --new)
      MODE="new"
      TARGET="${2:-}"
      shift
      [ -n "$TARGET" ] && shift
      ;;
    --yes)
      CONFIRM="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

exec python3 -c '
import json, os, sys, glob, shutil, uuid, subprocess
from datetime import datetime

proj_dir = sys.argv[1]
cwd = sys.argv[2]
mode = sys.argv[3]
target = sys.argv[4]
confirm = sys.argv[5] == "true"

def get_active_session_ids():
    # The ~/.claude/sessions/ registry is unreliable: it stores the session ID
    # from when Claude Code launched, but does not update after /resume.
    # Instead, we check if any live Claude process exists for this project,
    # and if so, treat the most recently modified .jsonl file as the active one.
    active = set()
    sessions_dir = os.path.expanduser("~/.claude/sessions")
    if not os.path.isdir(sessions_dir):
        return active

    has_live_claude = False
    for fname in os.listdir(sessions_dir):
        if not fname.endswith(".json"):
            continue
        try:
            with open(os.path.join(sessions_dir, fname)) as f:
                d = json.load(f)
            if d.get("cwd") != cwd:
                continue
            pid = d.get("pid")
            if pid is None:
                continue
            os.kill(pid, 0)
            result = subprocess.run(
                ["ps", "-p", str(pid), "-o", "comm="],
                capture_output=True, text=True
            )
            comm = result.stdout.strip().lower()
            if "claude" in comm or "node" in comm:
                has_live_claude = True
                break
        except (OSError, ProcessLookupError, Exception):
            pass

    if has_live_claude:
        # The active session is the most recently modified .jsonl file
        newest_sid = None
        newest_mtime = 0
        for fpath in glob.glob(os.path.join(proj_dir, "*.jsonl")):
            sid = os.path.basename(fpath)[:-6]
            if sid.startswith("agent-") or os.path.getsize(fpath) == 0:
                continue
            mtime = os.path.getmtime(fpath)
            if mtime > newest_mtime:
                newest_mtime = mtime
                newest_sid = sid
        if newest_sid:
            active.add(newest_sid)

    return active

def parse_sessions():
    sessions = []
    for fpath in glob.glob(os.path.join(proj_dir, "*.jsonl")):
        sid = os.path.basename(fpath)[:-6]
        if sid.startswith("agent-") or os.path.getsize(fpath) == 0:
            continue

        title = ""
        first_msg = ""
        msg_count = 0
        found_first = False

        with open(fpath) as f:
            for line in f:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                t = d.get("type", "")
                if t == "custom-title":
                    title = d.get("customTitle", "")
                elif t == "agent-name":
                    title = d.get("agentName", "")
                elif t == "user":
                    msg_count += 1
                    if not found_first and d.get("message"):
                        content = d["message"].get("content", "")
                        if isinstance(content, str):
                            first_msg = content
                        elif isinstance(content, list):
                            for block in content:
                                if block.get("type") == "text":
                                    first_msg = block.get("text", "")
                                    break
                        found_first = True

        if len(first_msg) > 80:
            first_msg = first_msg[:80] + "..."

        sessions.append({
            "sid": sid, "path": fpath, "title": title,
            "first_msg": first_msg, "msg_count": msg_count,
            "file_size": os.path.getsize(fpath),
            "mod_time": os.path.getmtime(fpath),
        })

    sessions.sort(key=lambda s: s["mod_time"], reverse=True)
    return sessions

def fmt_size(b):
    if b < 1024: return f"{b}B"
    if b < 1048576: return f"{b // 1024}K"
    return f"{b / 1048576:.1f}M"

def fmt_date(ts):
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")

active_ids = get_active_session_ids()
sessions = parse_sessions()

def fmt_session_line(s, active_ids):
    name = s["title"] or "(unnamed)"
    tag = " (active)" if s["sid"] in active_ids else ""
    date = fmt_date(s["mod_time"])
    size = fmt_size(s["file_size"])
    mc = s["msg_count"]
    fm = s["first_msg"]
    return f"{name}{tag}\n  {date} | {size} | {mc} msgs | {fm}"

if mode == "list":
    print(f"Sessions for: {cwd}")
    print()
    if not sessions:
        print("No sessions found.")
    else:
        for s in sessions:
            print(fmt_session_line(s, active_ids))
            print()
        print(f"Total: {len(sessions)} session(s)")
    print()
    print("Flags:")
    print("  --new \"name\"      Create a new named session")
    print("  --find \"query\"    Search sessions by name")
    print("  --delete \"name\"   Delete a session by name")
    print("  --delete          Delete all unnamed sessions")

elif mode == "find":
    if not target:
        print("Usage: sessions.sh --find \"query\"")
        sys.exit(1)
    query = target.lower()
    matches = [s for s in sessions if query in (s["title"] or "").lower()]
    print(f"Sessions matching: \"{target}\"")
    print()
    if not matches:
        print(f"No sessions found matching \"{target}\".")
    else:
        for s in matches:
            print(fmt_session_line(s, active_ids))
            print()
        print(f"Found: {len(matches)} session(s)")

elif mode == "new":
    if not target:
        print("Usage: sessions.sh --new \"session name\"")
        sys.exit(1)
    # Check if a session with this name already exists
    for s in sessions:
        if s["title"] == target:
            print(f"A session named \"{target}\" already exists.")
            sys.exit(1)
    sid = str(uuid.uuid4())
    fpath = os.path.join(proj_dir, sid + ".jsonl")
    with open(fpath, "w") as f:
        f.write(json.dumps({"type": "custom-title", "customTitle": target, "sessionId": sid}) + "\n")
    print(f"Created session: \"{target}\"")
    print()
    print("YOU MUST DO THE FOLLOWING:")
    print(f"  Step 1: Run /resume and select \"{target}\"")
    print(f"  Step 2: After resuming, run exactly:")
    print(f"          /rename {target}")
    print()
    print("Copy the /rename command above exactly as shown.")

elif mode == "delete":
    if target:
        matches = [s for s in sessions if s["title"] == target]
        if not matches:
            print(f"No session found with name: \"{target}\"")
            sys.exit(1)
        if confirm:
            deleted = 0
            for s in matches:
                sid = s["sid"]
                if sid in active_ids:
                    print(f"WARNING: Skipping \"{target}\" ({sid}) -- cannot delete an active session.")
                    continue
                os.remove(s["path"])
                sub = os.path.join(proj_dir, sid)
                if os.path.isdir(sub):
                    shutil.rmtree(sub)
                print(f"Deleted: {sid}")
                deleted += 1
            print(f"Deleted {deleted} session(s).")
        else:
            print("The following session(s) will be deleted:")
            print()
            for s in matches:
                sid = s["sid"]
                tag = " (ACTIVE - will be skipped)" if sid in active_ids else ""
                date = fmt_date(s["mod_time"])
                size = fmt_size(s["file_size"])
                fm = s["first_msg"]
                print(f"  {target} ({sid}){tag}")
                print(f"    {date} | {size} | {fm}")
            print()
            print("AWAITING_CONFIRMATION")
    else:
        unnamed = [s for s in sessions if not s["title"]]
        if not unnamed:
            print("No unnamed sessions found.")
            sys.exit(0)
        if confirm:
            deleted = 0
            for s in unnamed:
                sid = s["sid"]
                if sid in active_ids:
                    print(f"WARNING: Skipping unnamed session ({sid}) -- cannot delete an active session.")
                    continue
                os.remove(s["path"])
                sub = os.path.join(proj_dir, sid)
                if os.path.isdir(sub):
                    shutil.rmtree(sub)
                print(f"Deleted: {sid}")
                deleted += 1
            print(f"Deleted {deleted} unnamed session(s).")
        else:
            print("The following unnamed session(s) will be deleted:")
            print()
            for s in unnamed:
                sid = s["sid"]
                tag = " (ACTIVE - will be skipped)" if sid in active_ids else ""
                date = fmt_date(s["mod_time"])
                size = fmt_size(s["file_size"])
                fm = s["first_msg"]
                print(f"  (unnamed) -- {sid}{tag}")
                print(f"    {date} | {size} | {fm}")
            print()
            print(f"Total: {len(unnamed)} unnamed session(s)")
            print()
            print("AWAITING_CONFIRMATION")
' "$DIR" "$PWD" "$MODE" "$TARGET" "$CONFIRM"
