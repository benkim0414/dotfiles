#!/usr/bin/env bash
# PreToolUse hook (matchers: Read, NotebookRead, mcp__qmd__get,
#   mcp__qmd__multi_get, Bash, Grep):
# Block redundant reads when the same file+range is already in this session's
# context. Based on the community "read-once" pattern (Boucle, egorfedorov).
# Extended to catch Bash file-read commands and Grep content-mode on cached files.
#
# Cache (JSONL, append-only, last matching line wins per path):
#   ${XDG_RUNTIME_DIR:-$HOME/.cache}/claude/read-cache-<SESSION_ID>.jsonl
#   {"path":"/abs","mtime":1713200000,"ranges":[[0,-1]],"ts":1713203600}
#
# Escape hatches (any true → allow + record fresh entry):
#   - mtime changed on disk (external edit invalidated the cached view)
#   - requested (offset,limit) not covered by any prior range
#   - now - ts >= READ_ONCE_TTL (default 1200s; guards context compaction;
#     TTL=0 disables caching)
#   - READ_ONCE_DISABLE=1 set in the environment
#   - no session_id / file missing / stat failure / corrupt cache
#
# Diff mode (opt-in, READ_ONCE_DIFF=1):
#   On mtime change for a Read call, return only the diff instead of a full
#   re-read. Falls back to full re-read when diff > READ_ONCE_DIFF_MAX (40)
#   lines or the snapshot is missing. Snapshots stored under:
#   ${CACHE_DIR}/snapshots-${SESSION_ID}/
#   Bash and Grep bypass paths do not trigger diff mode.
#
# Silent exit 0 = allow. JSON permissionDecision="deny" = block the tool call.
# Range semantics match Claude Code's Read tool: offset/limit are line counts;
# limit == -1 means "whole file from offset".
#
# Hot path: fires on every Read, Bash, and Grep. Per-tool fast-exits run before
# sourcing the shared library to minimise overhead on the non-cached common case.
# The Read fast path retains the same 4 jq forks as the original single-tool hook.
set -euo pipefail

# NOTE: READ_ONCE_DISABLE=1 is an operator escape hatch. It is checked below,
# after stdin is parsed, so the bypass can be logged for audit purposes.
# Do not advertise this env var in deny messages — the agent reads them.

# ---------------------------------------------------------------------------
# Parse stdin once: all fields needed by any tool branch.
# SOH (\x01) separated -- tab is IFS-whitespace and collapses empty fields
# (e.g. Bash tool has no file_path, producing consecutive tabs that bash
# merges, shifting all subsequent fields left).
# ---------------------------------------------------------------------------
SESSION_ID="" TOOL_NAME="" FILE_PATH="" OFFSET=0 LIMIT=-1 COMMAND="" OUTPUT_MODE=""
IFS=$'\x01' read -r SESSION_ID TOOL_NAME FILE_PATH OFFSET LIMIT COMMAND OUTPUT_MODE < <(
  jq -r '[
    (.session_id // ""),
    (.tool_name // ""),
    (.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""),
    ((.tool_input.offset // 0) | tostring),
    ((.tool_input.limit // -1) | tostring),
    (.tool_input.command // ""),
    (.tool_input.output_mode // "")
  ] | join("")' 2>/dev/null
) || true

[[ "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || exit 0

# READ_ONCE_DISABLE=1: allow immediately, but log the bypass for audit.
if [[ "${READ_ONCE_DISABLE:-0}" == "1" ]]; then
  {
    _log_dir="${HOME}/.claude/logs"
    mkdir -p "$_log_dir" 2>/dev/null || true
    _log_date=$(date +%Y-%m-%d 2>/dev/null || true)
    _log_file="${_log_dir}/read-once-bypass-${_log_date}.log"
    if [[ -f "$_log_file" ]]; then
      _sz=$(stat -c %s "$_log_file" 2>/dev/null || stat -f %z "$_log_file" 2>/dev/null || echo 0)
      if (( _sz > 52428800 )); then
        mv "$_log_file" "${_log_file}.1" 2>/dev/null || true
      fi
    fi
    jq -cn \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
      --arg sid "$SESSION_ID" \
      --arg tool "$TOOL_NAME" \
      --arg cmd "${COMMAND:0:200}" \
      --arg path "$FILE_PATH" \
      --arg cwd "$PWD" \
      '{ts:$ts,session_id:$sid,tool:$tool,command:$cmd,path:$path,cwd:$cwd,event:"read_once_bypass"}' \
      >> "$_log_file" 2>/dev/null || true
  } &
  exit 0
fi

# ---------------------------------------------------------------------------
# Per-tool fast-exits (before sourcing library or touching the cache).
# ---------------------------------------------------------------------------

# Bash: exit early unless the command is a file-read invocation.
FILE_ARGS=()
if [[ "$TOOL_NAME" == "Bash" ]]; then
  # Match leading: optional whitespace, optional "sudo ", then a read-type tool.
  if ! [[ "$COMMAND" =~ ^[[:space:]]*(sudo[[:space:]]+)?(cat|head|tail|bat|view|less|more|sed)[[:space:]] ]]; then
    exit 0
  fi
  READ_TOOL="${BASH_REMATCH[2]}"

  # tail -f / --follow is a live stream, not a file read — allow it.
  if [[ "$READ_TOOL" == "tail" ]] && [[ "$COMMAND" =~ (^|[[:space:]])-[^[:space:]]*f([[:space:]]|$) ]]; then
    exit 0
  fi

  # Extract the portion of the command after the tool name, removing output
  # redirections (> or >>) so their targets are not mistaken for read args.
  _rest="${COMMAND#*"$READ_TOOL"}"
  _rest="${_rest%%>[^|]*}"   # strip anything after a non-piped >

  # Collect non-flag tokens as potential file arguments.
  _skip_next=0
  # Per-tool flags that consume the next token as a value.
  # cat/bat/view/less/more treat -n as a no-arg toggle (number lines), unlike
  # head/tail where -n N requires a value. A shared regex across unrelated tools
  # silently lets file paths slip past the cache as consumed flag values.
  case "$READ_TOOL" in
    head|tail) _skip_re='^-(n|c)$' ;;   # head/tail -n N | -c N
    sed)       _skip_re='^-(e|f)$' ;;   # sed -e EXPR | -f FILE
    *)         _skip_re='^$' ;;          # cat/bat/view/less/more — no value flags
  esac
  read -ra _tokens <<< "$_rest" || true
  _pipe_re='^[|<>]'
  for _tok in "${_tokens[@]}"; do
    if (( _skip_next )); then _skip_next=0; continue; fi
    [[ "$_tok" == "--" ]] && continue
    # Pipe or redirection: stop collecting.
    [[ "$_tok" =~ $_pipe_re ]] && break
    if [[ "$_tok" =~ ^- ]]; then
      # Options that consume the next token as their value (per-tool).
      [[ "$_tok" =~ $_skip_re ]] && _skip_next=1
      continue
    fi
    # Strip surrounding single or double quotes.
    _tok="${_tok#[\'\"]}" ; _tok="${_tok%[\'\"]}"
    [[ -n "$_tok" ]] && FILE_ARGS+=("$_tok")
  done

  [[ "${#FILE_ARGS[@]}" -gt 0 ]] || exit 0
fi

# Grep: exit early unless reading file content for a single path.
if [[ "$TOOL_NAME" == "Grep" ]]; then
  [[ "$OUTPUT_MODE" == "content" ]] || exit 0
  [[ -n "$FILE_PATH" ]] || exit 0
  [[ -d "$FILE_PATH" ]] && exit 0  # directory glob — not a single-file read
fi

# Read / NotebookRead / mcp__qmd__*: qmd docids ("#abc123") are not real paths.
if [[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "Grep" ]]; then
  [[ "$FILE_PATH" == \#* ]] && exit 0
  [[ -n "$FILE_PATH" ]] || exit 0
fi

# ---------------------------------------------------------------------------
# Shared initialisation.
# ---------------------------------------------------------------------------
TTL="${READ_ONCE_TTL:-1200}"
NOW="${EPOCHSECONDS:-$(date +%s)}"

CACHE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/claude"
mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0
# shellcheck disable=SC2034  # used by sourced read-once-cache.sh
CACHE="${CACHE_DIR}/read-cache-${SESSION_ID}.jsonl"

# Source shared helpers after fast-exits so the common non-cached Bash/Grep
# paths pay no sourcing cost.
# shellcheck source=../lib/read-once-cache.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/read-once-cache.sh"

# ---------------------------------------------------------------------------
# _check_path ABS OFFSET LIMIT
# Returns 0 to allow; returns 1 after writing deny JSON to stdout.
# ---------------------------------------------------------------------------
_check_path() {
  local file_path="$1" offset="$2" limit="$3"

  # Resolve symlinks (stow-managed dotfiles → canonical path).
  local abs
  abs=$(realpath -m "$file_path" 2>/dev/null \
    || grealpath -m "$file_path" 2>/dev/null \
    || echo "$file_path")

  # stat: existence + mtime + size. Any failure → allow (let the tool error).
  local stat_out
  stat_out=$(stat -c '%Y %s' "$abs" 2>/dev/null \
    || stat -f '%m %z' "$abs" 2>/dev/null) || return 0
  local current_mtime size
  read -r current_mtime size <<< "$stat_out"
  [[ "$current_mtime" =~ ^[0-9]+$ && "$current_mtime" -gt 0 ]] || return 0

  # Cache lookup.
  local status p_mtime p_ts covered extended
  status=NEW p_mtime=0 p_ts=0 covered=false extended="[[${offset}, ${limit}]]"
  IFS=$'\t' read -r status p_mtime p_ts covered extended < <(
    rc_lookup "$abs" "$offset" "$limit"
  ) || true

  # First time seeing this path in this session.
  if [[ "$status" != "HIT" ]]; then
    rc_record "$abs" "$current_mtime" "[[${offset}, ${limit}]]"
    # Diff mode: stash a snapshot of the full file on first read.
    if [[ "${READ_ONCE_DIFF:-0}" == "1" && "$limit" == "-1" && "$offset" == "0" ]]; then
      local snap_dir="${CACHE_DIR}/snapshots-${SESSION_ID}"
      mkdir -p "$snap_dir" 2>/dev/null || true
      local slug
      slug=$(rc_path_slug "$abs") || true
      [[ -n "$slug" ]] && cp -- "$abs" "${snap_dir}/${slug}" 2>/dev/null || true
    fi
    return 0
  fi

  # File changed since last read.
  if [[ "$p_mtime" != "$current_mtime" ]]; then
    # Diff mode (Read/NotebookRead/qmd only): return diff instead of full re-read.
    if [[ "${READ_ONCE_DIFF:-0}" == "1" \
        && "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "Grep" ]]; then
      local snap_dir="${CACHE_DIR}/snapshots-${SESSION_ID}"
      local slug
      slug=$(rc_path_slug "$abs") || true
      local snap="${snap_dir}/${slug:-}"
      if [[ -n "${slug:-}" && -f "$snap" ]]; then
        local diff_out diff_lines max_lines
        diff_out=$(diff -u "$snap" "$abs" 2>/dev/null || true)
        diff_lines=$(printf '%s\n' "$diff_out" | wc -l)
        max_lines="${READ_ONCE_DIFF_MAX:-40}"
        if [[ -n "$diff_out" && "$diff_lines" -le "$max_lines" ]]; then
          cp -- "$abs" "$snap" 2>/dev/null || true
          rc_record "$abs" "$current_mtime" "[[${offset}, ${limit}]]"
          local tokens
          tokens=$(( size / 4 ))
          local reason="read-once: ${abs} changed since last read (~${tokens} tokens). Diff (${diff_lines} lines) below — apply this instead of re-reading.
${diff_out}"
          jq -cn --arg r "$reason" '{
            hookSpecificOutput: {
              hookEventName: "PreToolUse",
              permissionDecision: "deny",
              permissionDecisionReason: $r
            }
          }'
          return 1
        fi
      fi
    fi
    rc_record "$abs" "$current_mtime" "[[${offset}, ${limit}]]"
    return 0
  fi

  # Cache entry expired (guards context compaction after long sessions).
  if (( NOW - p_ts >= TTL )); then
    rc_record "$abs" "$current_mtime" "[[${offset}, ${limit}]]"
    return 0
  fi

  # Requested range not fully covered by any cached range.
  if [[ "$covered" != "true" ]]; then
    rc_record "$abs" "$current_mtime" "$extended"
    return 0
  fi

  # Fully covered and unchanged: deny.
  local age
  age=$(( NOW - p_ts ))
  rc_deny "$abs" "$age" "$size"
  return 1
}

# ---------------------------------------------------------------------------
# Dispatch: iterate files for Bash; single path for Grep and Read-family.
# _check_path returns 1 after emitting deny JSON — exit 0 to flush it.
# ---------------------------------------------------------------------------
if [[ "$TOOL_NAME" == "Bash" ]]; then
  for _file in "${FILE_ARGS[@]}"; do
    _check_path "$_file" 0 -1 || exit 0
  done
elif [[ "$TOOL_NAME" == "Grep" ]]; then
  _check_path "$FILE_PATH" 0 -1 || exit 0
else
  _check_path "$FILE_PATH" "$OFFSET" "$LIMIT" || exit 0
fi

exit 0
