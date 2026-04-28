#!/usr/bin/env bash
# PreCompact/SessionEnd hook: write a session stub to wiki/raw/captures/.
# Pure shell + jq — zero Claude token cost per session.
set -euo pipefail

WIKI_VAULT="${WIKI_VAULT:-$HOME/workspace/wiki}"
CAPTURES_DIR="$WIKI_VAULT/raw/captures"
LOG_FILE="$HOME/.claude/logs/wiki-capture.log"

_log() {
  local msg="$*"
  printf '[%s] wiki-capture: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" \
    >> "$LOG_FILE" 2>/dev/null || true
}

# Guard: wiki vault must exist and be a git repo.
if [[ ! -d "$WIKI_VAULT" ]] || ! git -C "$WIKI_VAULT" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Parse stdin.
INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
HOOK_EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)

# Validate session_id: must be a UUID.
if [[ ! "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  exit 0
fi

# Fallback: derive transcript path from cwd-slug + session_id.
if [[ -z "$TRANSCRIPT" && -n "$CWD" ]]; then
  CWD_SLUG=$(printf '%s' "$CWD" | sed 's|^/||; s|/|-|g')
  TRANSCRIPT="$HOME/.claude/projects/${CWD_SLUG}/${SESSION_ID}.jsonl"
fi

TRIGGER=$(printf '%s' "$HOOK_EVENT" | tr '[:upper:]' '[:lower:]')

# Extract data from transcript in a single jq pass.
TURNS=0 TOOL_CALLS=0 FIRST_PROMPT="" LAST_PROMPT="" DURATION_MIN=0 BRANCH="" FILES_TOUCHED=""

if [[ -f "$TRANSCRIPT" ]]; then
  PARSED=$(jq -rn '
    [inputs] as $lines |

    # Real human prompts: type=user, userType=external, content is a plain string
    # not starting with "<" (system/command output) or known continuation banners.
    (
      $lines
      | map(
          select(
            .type == "user"
            and .userType == "external"
            and (.message.content | type) == "string"
            and (.message.content | startswith("<") | not)
            and (.message.content | startswith("This session is being continued") | not)
          )
        )
    ) as $prompts |

    # Tool uses across assistant messages
    (
      $lines
      | map(
          select(.type == "assistant")
          | .message.content // []
          | arrays
          | map(select(.type == "tool_use"))
        )
      | flatten
    ) as $tools |

    # Files touched by mutating tools only; use | as separator (safe: paths have no |)
    (
      $tools
      | map(
          select(.name == "Write" or .name == "Edit" or .name == "MultiEdit" or .name == "NotebookEdit")
          | (.input.file_path // .input.notebook_path // "")
        )
      | map(select(length > 0))
      | unique
      | join("|")
    ) as $files |

    # Git branch from first message that has it
    (($lines | map(select(.gitBranch != null and .gitBranch != "")) | .[0].gitBranch) // "") as $branch |

    # Timestamps for duration
    (($lines | map(select(.timestamp != null)) | .[0].timestamp) // "") as $t0 |
    (($lines | map(select(.timestamp != null)) | last.timestamp) // "") as $t1 |

    [
      ($prompts | length),
      ($tools | length),
      ($prompts[0].message.content // "" | .[0:200]),
      ($prompts[-1:][0].message.content // "" | .[0:200]),
      $files,
      $branch,
      $t0,
      $t1
    ] | @tsv
  ' "$TRANSCRIPT" 2>/dev/null || true)

  if [[ -n "$PARSED" ]]; then
    IFS=$'\t' read -r TURNS TOOL_CALLS FIRST_PROMPT LAST_PROMPT FILES_RAW BRANCH T0 T1 <<< "$PARSED"

    # Compute duration in minutes (GNU date; gracefully skip on failure).
    if [[ -n "$T0" && -n "$T1" ]]; then
      TS0=$(date -d "$T0" +%s 2>/dev/null || echo 0)
      TS1=$(date -d "$T1" +%s 2>/dev/null || echo 0)
      (( TS0 > 0 && TS1 > TS0 )) && DURATION_MIN=$(( (TS1 - TS0) / 60 ))
    fi

    # Build YAML list for files_touched (| was used as path separator in jq).
    if [[ -n "$FILES_RAW" ]]; then
      IFS='|' read -ra FILE_ARRAY <<< "$FILES_RAW"
      for f in "${FILE_ARRAY[@]}"; do
        [[ -n "$f" ]] && FILES_TOUCHED+="  - ${f}"$'\n'
      done
    fi
  fi
fi

# Apply thresholds: skip trivial sessions (no tool use, or under 1 minute).
# Turn count is unreliable for compacted transcripts, so we don't gate on it.
if (( TOOL_CALLS < 1 || DURATION_MIN < 1 )); then
  exit 0
fi

# Compute slug from first human prompt.
TODAY=$(date +%Y-%m-%d)
SLUG=$(printf '%s' "$FIRST_PROMPT" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c '[:alnum:] ' ' ' \
  | tr -s ' ' \
  | head -c 60 \
  | sed 's/ /-/g; s/^-//; s/-$//')
[[ -z "$SLUG" ]] && SLUG="session-${SESSION_ID:0:8}"

# Idempotency: if a stub already exists for this session_id, update it in place.
mkdir -p "$CAPTURES_DIR"
EXISTING=$(grep -rl "session_id: ${SESSION_ID}" "$CAPTURES_DIR" 2>/dev/null | head -1 || true)
if [[ -n "$EXISTING" ]]; then
  OUT="$EXISTING"
else
  OUT="$CAPTURES_DIR/${TODAY}--${SLUG}--claude-session.md"
fi

# Build files_touched frontmatter block.
FILES_BLOCK=""
if [[ -n "$FILES_TOUCHED" ]]; then
  FILES_BLOCK=$'files_touched:\n'"${FILES_TOUCHED}"
fi

# Write stub.
cat > "$OUT" <<STUB
---
type: capture
source: claude-session
created: ${TODAY}
session_id: ${SESSION_ID}
cwd: ${CWD}
branch: ${BRANCH:-unknown}
trigger: ${TRIGGER}
transcript: ${TRANSCRIPT}
duration_min: ${DURATION_MIN}
turns: ${TURNS}
${FILES_BLOCK}---

# Session capture: ${SLUG}

**First prompt:** ${FIRST_PROMPT}

**Last prompt:** ${LAST_PROMPT}

To curate, run the wiki's local ingest skill against unconsumed entries in raw/captures/.

To inspect the full transcript:
    jq -c '.' < ${TRANSCRIPT}
STUB

_log "wrote $(basename "$OUT") (trigger=${TRIGGER}, turns=${TURNS}, tool_calls=${TOOL_CALLS}, duration=${DURATION_MIN}min)"
