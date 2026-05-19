# Read-once hook hardening — design

Date: 2026-05-19
Status: design (awaiting approval)
Scope: bug fixes + cache GC + retry detection + diff-mode redesign + tests + docs

## Problem

The read-once hook (`claude/.claude/hooks/read-once.sh` + `lib/read-once-cache.sh`)
is installed and firing — 141 deny events recorded in dotfiles project sessions,
177 active cache files in `~/.cache/claude/` totalling 809KB. Investigation
across historical sessions surfaced multiple defects and behavioural issues:

1. **`mcp__qmd__multi_get` matcher is dead code.** The tool input field is
   `pattern` (a glob), not `path`. The hook's jq extractor reads
   `file_path // notebook_path // path`, gets an empty string, and exits at the
   "no file path" fast-exit. The matcher claims coverage but the hook does
   nothing for this tool.
2. **`sed -i` is mis-classified as a read.** The Bash branch matches `sed` as
   a read tool. `-i` / `--in-place` is not in the per-tool skip-flag list, so
   the trailing filename becomes a `FILE_ARG`. A write disguised as a Bash
   command can be denied as a redundant read.
3. **Diff mode is dead in practice.** `READ_ONCE_DIFF=1` is never set. Zero
   snapshot directories exist on disk despite 30+ days of cache history. The
   feature also has a correctness gap: snapshots are only stored when the
   first read is `offset=0, limit=-1`, so any first partial read silently
   loses diff capability for subsequent full reads.
4. **No cache GC.** Cache files accumulate indefinitely. 8 files are older
   than 7 days; the oldest dates to mid-April. Footprint is small now (under
   1MB) but unbounded.
5. **Agent retry loop / workaround culture.** Historical sessions show the
   same file denied 8x, 15x, 36x, even 48x in a single session window with
   no behavioural change. Audit logs show 20+ unique "bypass" descriptions
   where agents `touch`, `cp`, or `python3 heredoc` files to force re-reads.
   The deny message is read but ignored.
6. **Multiple smaller bugs** — bypass log rotation never trims its `.1`
   file; `realpath -m` is GNU-only; `FOO=bar cat file` and `command cat file`
   prefixes slip past the Bash read-tool regex; concurrent JSONL appends are
   safe in practice but undocumented.

## Goals

- Fix correctness bugs without changing the JSONL cache format in a
  backwards-incompatible way.
- Cap disk usage with a two-tier GC (in-hook opportunistic + `SessionEnd`).
- Make the deny message harder for the agent to ignore via escalating
  wording and touch-bypass detection.
- Make diff mode actually useful (default-on, correct snapshotting, size
  guards).
- Add a test suite so future changes don't regress.

## Non-goals

- Rewriting the cache to a database (SQLite, leveldb). The JSONL append
  model is fine; only schema additions are in scope.
- Detecting all bypass workarounds (`cp`, `python`, `wc -l + tail`). Touch
  is the dominant one per audit logs; broader detection is out of scope.
- A daemon or long-running watcher. All work happens inside the existing
  hook + a new `SessionEnd` hook.
- UI / dashboard. Telemetry stays in the existing audit log + cache files.

## Architecture

Files touched:

| Path | Change |
|---|---|
| `claude/.claude/hooks/read-once.sh` | Bug fixes, touch detection, diff-mode redesign, opportunistic GC, deny-wording escalation |
| `claude/.claude/lib/read-once-cache.sh` | Schema bump (`denies` field), new helpers (`rc_escalate_msg`, `rc_record_touch`) |
| `claude/.claude/hooks/read-once-gc.sh` | NEW. `SessionEnd` hook, prunes stale cache + snapshots |
| `claude/.claude/settings.base.json` | Drop `mcp__qmd__multi_get` from matcher, add `SessionEnd` matcher for GC hook |
| `claude/.claude/tests/read-once/run.sh` | NEW. Test runner |
| `claude/.claude/tests/read-once/cases/*.sh` | NEW. Per-scenario test cases |
| `claude/.claude/tests/read-once/fixtures/*.json` | NEW. Sample stdin payloads |
| `claude/.claude/docs/read-once.md` | NEW. Operator reference |

No new external dependencies. No new daemon. No persistent state outside
the existing cache directory.

## Section A — Bug fixes

### A.1 Drop `mcp__qmd__multi_get` from matcher

`settings.base.json`: change matcher to
`Read|NotebookRead|mcp__qmd__get|Bash|Grep`. Document the carve-out in the
hook header (qmd `pattern` is a glob; expansion would exceed the 3s budget
and qmd already de-duplicates server-side).

### A.2 Recognise `sed -i` as a write, not a read

In the Bash branch (`read-once.sh:96` onwards):

- After matching `sed` as the read-tool, scan `_tokens` for `-i`,
  `--in-place`, or `-i ''` / `-i ""` (BSD form, optional empty suffix) and
  any `-i SUFFIX`.
- If present, exit 0 immediately (allow, no cache lookup).
- Also exit 0 if no positional file arguments remain after token parsing
  (sed reading stdin from a pipe).

### A.3 Snapshot on every first read

In `_check_path`, drop the `offset == 0 && limit == -1` guard around the
snapshot copy. Snapshot the full file on first cache miss regardless of
range. Apply a size cap: skip snapshot if file size > `READ_ONCE_DIFF_MAX_BYTES`
(default 262144 = 256KB). Re-snapshot on every mtime change after a diff is
returned (already done; keep behaviour).

### A.4 Bypass log rotation

The daily filename `read-once-bypass-${_log_date}.log` already rotates per
day. The 50MB size-check + `.log → .log.1` mv block is redundant and the
`.1` file is never trimmed. Remove the size-check block entirely.

### A.5 Accept `env`, `command`, `builtin` prefixes in Bash branch

Extend the read-tool regex prefix group to also tolerate:

- `env [VAR=val ...] <tool>`
- `command <tool>`
- `builtin <tool>` (rare; included for completeness)
- One or more `VAR=val ` assignments (`FOO=bar cat file`)

Reject `\cat` (backslash escape) — too rare to justify the parsing
complexity.

### A.6 realpath portability

Document the existing fallback chain in the header. Add a final
PWD-relative resolution attempt if both `realpath -m` and `grealpath -m`
fail. Implementation prerequisite: verify `coreutils` is in the Brewfile;
add it if missing.

### A.7 Document JSONL atomicity

Header comment: each `rc_record` line is well under PIPE_BUF (4096 bytes),
so POSIX `>>` appends are atomic in practice. No code change.

### A.8 Range coverage clarification (not a bug)

Adjacent / non-overlapping cached ranges intentionally do not coalesce.
The cache records each new range as an additional element; coverage is a
"does any single range fully contain the requested range" check. This is
correct under the current semantics. Document the choice in the header.

## Section B — Cache GC

### B.1 Tier A — opportunistic prune inside `read-once.sh`

After the fast-exits, before sourcing the cache library:

- Check sentinel `${CACHE_DIR}/.last-read-once-prune` mtime.
- If newer than 24h, skip.
- Otherwise `touch` the sentinel and `find` `read-cache-*.jsonl` older
  than `READ_ONCE_GC_DAYS` (default 7) — delete them and their matching
  `snapshots-<sid>/` directory.
- Wrap in `{ ... } &; disown` so the prune does not block the hook.
- Operator opt-out: `READ_ONCE_GC_DISABLE=1`.

### B.2 Tier B — `SessionEnd` hook

New file `claude/.claude/hooks/read-once-gc.sh`, matcher `SessionEnd` in
`settings.base.json`. On session end:

- Read `session_id` from stdin.
- Delete `${CACHE_DIR}/read-cache-${SESSION_ID}.jsonl` and
  `${CACHE_DIR}/snapshots-${SESSION_ID}/` if the parent transcript at
  `~/.claude/projects/*/${SESSION_ID}.jsonl` is also missing or older
  than `READ_ONCE_GC_DAYS`.
- Otherwise leave them — they may still be useful on session resume.

Also a final orphan sweep: snapshot dirs with no matching cache file
deleted.

### B.3 Env reference

| Var | Default | Effect |
|---|---|---|
| `READ_ONCE_GC_DAYS` | 7 | Retention for cache + snapshot files |
| `READ_ONCE_GC_DISABLE` | unset | Disable both tiers when set to `1` |

## Section C — Retry / touch detection

### C.1 Schema bump: `denies` field

Cache entry becomes:

```json
{"path":"/abs","mtime":1713200000,"ranges":[[0,-1]],"ts":1713203600,"denies":0}
```

`denies` is the cumulative deny count for this path in this session. Set
to 0 on every cache miss / mtime change / range extension / TTL expiry
(i.e. every `rc_record` call). Incremented inside `_check_path` before
emitting deny by appending a new JSONL line with `denies = prior + 1`.
`rc_lookup` already takes `last` per path so it picks up the new field
without code change.

### C.2 Escalation ladder

`rc_deny` becomes `rc_escalate_deny` and takes `denies` as a third arg:

| Denies | Wording |
|---|---|
| 0 | "read-once: `<path>` in context (read Xs ago, unchanged, ~N tokens). Use loaded content. Invalidate: edit file or request different offset/limit." |
| 1-2 | "read-once: `<path>` STILL in context (deny #N, read Xs ago). Stop re-reading. Use content already loaded OR change approach." |
| 3-5 | "read-once: `<path>` DENY #N. File unchanged since first read. Re-reads will keep failing. Use content from context OR change task plan." |
| 6+ | "read-once: `<path>` DENY #N — retry loop. Operator escape: `READ_ONCE_DISABLE=1` in env. Otherwise abandon this approach." |

Touch override (see C.3) jumps straight to rank 3+ wording.

### C.3 Touch-bypass detection

New sidecar JSONL: `${CACHE_DIR}/touch-events-${SESSION_ID}.jsonl`. Capped
at 100 entries; oldest pruned via `tail -n 100` rewrite on append.

Bash branch additions:

- Detect `touch <path>` (also `touch -m`, `touch -t TS`, `touch -d`).
  Extract the path argument(s) using the same token parser as the
  read-tool branch (with `_skip_re='^-(t|d|r)$'`).
- For each touched path: append `{path, ts, event:"touch_invalidate"}`
  to the touch-events sidecar.
- If the touched path matches a recently-cached entry (`mtime` unchanged
  since last `rc_record`, ts within 5s), emit a permissionDecision deny
  with wording:

  > "read-once: `<path>` DENY — touch on recently-read file looks like
  > a read-once bypass. To force re-read: edit content, or set
  > `READ_ONCE_DISABLE=1`."

  This blocks the `touch` itself, breaking the workaround. The
  `READ_ONCE_DISABLE` hint appears earlier here than in the read-side
  ladder (C.2) because a `touch`-based bypass attempt already signals
  high motivation to circumvent the hook; offering the official escape
  is preferable to encouraging further workarounds.

- Otherwise allow the `touch`. Next read will cache-miss naturally.

Deny side (`_check_path`): when emitting a normal deny, scan the
touch-events sidecar for the same path within the last 30s. If found,
escalate immediately to rank 3 wording with the additional sentence:
"Touch invalidation detected at Ts."

### C.4 Counter reset

Any call to `rc_record` (cache miss, mtime change, range extension, TTL
expiry, post-touch re-read) writes `denies: 0`. The escalation counter
is therefore session-local and resets whenever the cache entry rolls.
The counter does not survive a session restart: the cache file is keyed
by `SESSION_ID`, so a resumed session starts with a fresh, empty cache
and an empty deny counter.

## Section D — Diff mode redesign

### D.1 Default on

Flip default to `READ_ONCE_DIFF=1`. Operator opt-out via
`READ_ONCE_DIFF=0`. Justification: feature is dead in practice because
nobody opts in; default-on exercises it and the size guards bound cost.

### D.2 Snapshot semantics

Per A.3: snapshot full file unconditionally on first cache miss, subject
to `READ_ONCE_DIFF_MAX_BYTES` (default 256KB).

### D.3 Snapshot directory cap

Cap `${CACHE_DIR}/snapshots-${SESSION_ID}/` at 50 files. On overflow,
evict oldest by mtime. Implemented inline via `ls -t | tail -n +51 | xargs rm -f`
after a snapshot copy.

### D.4 Diff fallback rules

Fall back to a normal allow (full re-read) when any of the following hold:

- Snapshot missing (size-guard skipped it).
- Snapshot is binary or `diff -u` exits with `cannot compare`.
- Diff exceeds `READ_ONCE_DIFF_MAX` lines (default 40).
- Current file size > 4× snapshot size (heuristic for rewrites — diff
  would be larger than the file itself).

### D.5 Token estimate in diff message

Include `~N tokens` (= `diff_size / 4`) in the diff-mode deny reason so
the agent sees the savings versus a full re-read.

### D.6 Env reference

| Var | Default | Effect |
|---|---|---|
| `READ_ONCE_DIFF` | 1 | Enable diff mode (was 0). Set to `0` to disable |
| `READ_ONCE_DIFF_MAX` | 40 | Max diff lines before falling back to allow |
| `READ_ONCE_DIFF_MAX_BYTES` | 262144 | Skip snapshot for files larger than this |

## Section E — Test suite

### E.1 Location and runner

`claude/.claude/tests/read-once/run.sh` — sources test helpers, iterates
`cases/*.sh`, prints per-case pass/fail, exits nonzero on any failure.
Each case sources the runner and uses `assert_*` helpers (assert_deny,
assert_allow, assert_jsonl_contains, etc.).

### E.2 Isolation

Each case starts with:

- `CACHE_DIR=$(mktemp -d)`
- `SESSION_ID="11111111-1111-1111-1111-111111111111"` (or scenario-specific)
- A fresh `tmpfile` for the file under test
- Optional pre-seeding of cache via `rc_record`

No shared global state. Cleanup via `trap rm -rf "$CACHE_DIR"` on EXIT.

### E.3 Required coverage

- A.1 — settings matcher excludes `mcp__qmd__multi_get` (assertion in
  test, plus a stub test that sends a `mcp__qmd__multi_get` payload and
  verifies no cache mutation).
- A.2 — `sed -i 's/x/y/' file` exits 0 with no cache mutation. `sed -i ''
  's/x/y/' file` (BSD form) likewise. `sed 's/x/y/'` (no file) likewise.
  `sed 's/x/y/' file` (read mode) does mutate cache.
- A.3 — partial first read snapshots full file. Full re-read after mtime
  change returns a diff (when small) or full re-read (when large).
- A.4 — bypass log rotation block is gone (smoke test reads the hook
  source for absence of the `mv ... .1` line).
- A.5 — `env FOO=bar cat file`, `FOO=bar cat file`, `command cat file`,
  `cat file` all hit cache. `\cat file` skips (documented limitation).
- B.1 — opportunistic prune deletes a stale cache file when sentinel is
  older than 24h.
- B.2 — `SessionEnd` GC hook deletes the just-ended session's cache file
  when transcript missing.
- C.1 — `denies` field present after first deny, increments on second.
- C.2 — wording template matches expected string for ranks 0, 1, 3, 6.
- C.3 — touch on recently-read file is denied. Touch on cold path is
  allowed. Touch-detected re-read uses escalated wording.
- D.1 — diff mode default-on (no env set, cache + mtime change → diff
  returned). Setting `READ_ONCE_DIFF=0` reverts to full re-read.
- D.3 — snapshot dir cap evicts oldest after 51st snapshot.
- D.4 — large diff falls back to allow. Binary file falls back to allow.
- General — `READ_ONCE_DISABLE=1` allows + writes bypass-log entry.

### E.4 Wiring

`claude-sync` script gains an optional `--test` flag that invokes
`claude/.claude/tests/read-once/run.sh` after sync. CI integration is
out of scope (no CI in this repo); the runner exists so changes can be
manually verified.

## Section F — Docs

### F.1 Header comment in `read-once.sh`

Update to reflect:

- New env vars: `READ_ONCE_GC_DAYS`, `READ_ONCE_GC_DISABLE`,
  `READ_ONCE_DIFF_MAX_BYTES`. Diff default now on.
- Touch-bypass detection behaviour.
- GC behaviour (two-tier).
- Matcher change (no `mcp__qmd__multi_get`).
- JSONL append atomicity note (PIPE_BUF safety).
- Range coalescing decision (no coalescing by design).

### F.2 Operator guide — `claude/.claude/docs/read-once.md`

Sections:

- Overview (what it does, why it exists).
- Env var reference (all of `READ_ONCE_*`).
- Bypass instructions (`READ_ONCE_DISABLE=1`).
- Cache layout + manual clear (`rm ~/.cache/claude/read-cache-*.jsonl`).
- Troubleshooting: false positives, hook timeouts, stuck cache.
- "Why is my touch denied" — pointer to C.3.

## Implementation order

The writing-plans skill will sequence implementation. Suggested order
(roughly safest-first, to allow early commits):

1. A.1 — matcher drop. One-line settings change.
2. A.4 — bypass log rotation removal. One-block deletion.
3. A.7 + A.8 — header comment additions. No code change.
4. A.6 — realpath portability + Brewfile verify.
5. A.5 — Bash regex prefix extension.
6. A.2 — `sed -i` write detection.
7. E.1–E.3 — test suite scaffolding + tests for A.1, A.2, A.5.
8. B.2 — `SessionEnd` GC hook.
9. B.1 — opportunistic prune in `read-once.sh`.
10. A.3 + D.2 + D.3 + D.4 — diff-mode snapshot redesign.
11. D.1 + D.5 + D.6 — diff-mode default flip + token estimate + env docs.
12. C.1 + C.2 — denies counter + escalation ladder.
13. C.3 + C.4 — touch detection sidecar + deny override.
14. E test cases for B, C, D.
15. F.1 + F.2 — final docs pass.

## Open questions

None. All design points agreed in brainstorming.
