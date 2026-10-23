# Plan: context-bar mod
From: [spec.md](spec.md). Status: draft.

## Files that change

Paths are relative to the `claude/` package, except the last one, which is
at the repo root.

- `.claude/mods/context-bar/.claude-plugin/plugin.json`: `name`
  `context-bar`, `version` `0.1.0`, a one-line `description`, `types`
  `./types/index.d.ts`
- `.claude/mods/context-bar/hooks/hooks.json`:
  `{ "modules": ["./register.tsx"] }`
- `.claude/mods/context-bar/hooks/layout.ts`: pure helpers with no `$`:
  - `shortTokens(n)`: R5's short format (`950`, `4.2k`, `17k`, `1.02M`);
  - `percent(tokens, window)`: whole percent, with any non-zero share
    shown as at least `1%`;
  - `labelFor(row)`: R5's label map, chosen by `kind` first;
  - `reduce(usage)`: `SessionUsage` → `Reading | null` (R2, R10);
  - `apportion(parts, width)`: R3's three steps, returning cell counts;
  - `layout(reading, width)`: `Row[] | null` (R1, R4–R7).
- `.claude/mods/context-bar/hooks/register.tsx`: the `session.start`,
  `turn.complete` and `session.compact` hooks, `/context-bar`, `refresh`,
  `clear` and the serial `publish` queue with its `epoch` check, and the
  `AbovePrompt` render hook (R8–R16)
- `.claude/mods/context-bar/hooks/layout.test.ts` and
  `hooks/register.test.tsx`: `claude plugin test` suites
- `.claude/mods/context-bar/types/index.d.ts`: the `PluginState` contract,
  with `Part` and `Reading` declared inside it. It must be self-contained:
  no `import` lines (the mermaid-ascii spike found that `claude plugin
  validate` refuses them)
- `.claude/mods/context-bar/tsconfig.json`:
  `{ "extends": "./.claude-plugin/types/tsconfig.json" }`
- `.claude/settings.json`: `env.CLAUDE_CODE_PLUGIN_DIRS` becomes
  `~/.claude/mods/mermaid-ascii:~/.claude/mods/context-bar` (R17)
- `CLAUDE.md` (repo root): a `context-bar` entry under "Mods", next to
  mermaid-ascii: what it shows, `/context-bar` to toggle it, nothing to
  install

`.gitignore` already covers `claude/.claude/mods/*/.claude-plugin/types/`.
There is no `render/` folder and no `node_modules`, so `.stow-local-ignore`
does not change.

## Order of work

Each step is one commit, test first where there is a test to write. The
work happens in this worktree; Stow and live checks wait for the merge.
Git runs as `/usr/bin/git`, because RTK's rewrite of `git` is refused
inside the worktree.

1. **Spike: background `$` calls and a held `usage()`.** Two assumptions
   R12 and R13 rest on, which no example covers:
   - **(a)** A hook may start `void work($)` and return. Calls that
     `work` makes on `$` after the hook has resolved (`$.session.usage`, a
     state write) still run, and the write redraws a mounted band.
   - **(b)** A test's own `on('session.usage', …)` hook can stand in for
     the engine. It can answer a promise the test resolves by hand, one
     that never resolves, and a rejection (expected as `{ deny }`, as
     mermaid-ascii found for `process.run`; a hook that throws is skipped,
     not turned into a rejection). In the same way, a test's
     `on('state.set', …)` hook can hold one write open until released,
     while later writes queue behind it.

   It is a throwaway mod at `.spike/background-usage/` in this worktree's
   root. That is outside the `claude` package, so Stow never sees it, and
   it is never staged. Run it with `claude plugin test`, then delete the
   folder.
   - **Both pass:** keep the spec's design.
   - **(a) fails:** schedule the refresh with `$.clock.after(0, …)`, which
     mermaid-ascii proved runs outside drawing, and update the spec's
     Events section and R12.
   - **(b) fails:** find what the kit offers to stub `$.session.usage`
     (`mock.*` in `claude-code/testing`), and record it here before
     step 4.

   Record the result in this file under step 1. No commit in the repo
   unless the spec changes.
2. **Scaffold and the arithmetic.** `plugin.json`, `hooks.json`,
   `types/index.d.ts`, `tsconfig.json`, a stub `register.tsx` that only
   returns `next(e)`, and in `layout.ts` the functions `shortTokens`,
   `percent`, `labelFor` and `apportion`. Write `layout.test.ts` first:
   - **`shortTokens`:** `0`, `950`, `4.2k`, `17k`, `897k`, `999k`, `1M`,
     `1.02M`. Also check the R7 bound: no value is longer than 5 columns
     up to `9.99M`;
   - **`percent`:** 0 is `0%`, 4.2k of 1M is `1%`, 17k of 1M is `2%`;
   - **`labelFor`:** every row of R5's table, an unknown name lowercased,
     and `free` and `buffer` labelled `free` and `reserved` whatever their
     `name`;
   - **`apportion`:** first an invariant checked in every case: every
     count is ≥ 0 and the counts sum to `width`. Then the spec's cases:
     - three rows of 100 in a window of 100 at width 60 give
       `[20, 20, 20]`;
     - 2 large rows plus 5 small ones at width 72: each small row gets 1
       cell, taken from the largest;
     - 9 parts of distinct, similar sizes in 6 cells: the 6 largest get 1
       cell each, the other 3 get 0;
     - skewed and crowded: `[1000, 9, 8, 7]` at width 2 gives
       `[1, 1, 0, 0]`. Largest remainder alone gives `[2, 0, 0, 0]`;
     - a 0-token part gets 0 cells, and a 1-token part gets 1;
     - remainder ties go to the earlier part, and donor ties come from the
       later part;
     - `D = 0` gives all free cells;
     - property check: random parts (seeded, so the run repeats), widths 1
       to 120, 500 runs, some of them skewed (one part 1000× the others).
       Every run holds the invariant, plus a rule that depends on the
       number of non-zero parts:
       - `k ≤ width`: every non-zero part has at least one cell;
       - `k > width`: the `width` largest parts (ties broken by bar order)
         have exactly one cell each, and all others have 0.

     Mutation-check `apportion`: removing step 3's redistribution for
     `k > width`, and removing it for `k ≤ width`, must each fail at least
     one test.
3. **Reduce and layout.** In `layout.ts`, the functions `reduce` and
   `layout`, test first:
   - **`reduce`:**
     - `used`, `free`, `buffer` and `deferred` rows are sorted by `kind`,
       with `deferred` dropped;
     - a missing `free` row gives `free` 0, and a missing `buffer` gives
       `reserved: null`;
     - no `breakdown`, or no `used` row, gives `null`;
     - `compactsAt` is `null` when `isAutoCompactEnabled` is false or the
       threshold is missing;
   - **`layout`:**
     - the intent's example at width 72: the header reads
       `◆ context … 90k of 1M · compacts at 99%`, and the legend entries
       read as the spec lists them, ending in `free 897k` and
       `reserved 13k`;
     - with auto-compact off there is no `compacts at` and no reserved
       entry or cells;
     - over the window, the header reads `1.02M of 1M` and every cell is
       used;
     - widths 80, 60, 59, 40, 39, 20 and 19 match R7's tiers (19 gives
       `null`). At every width from 19 to 120, no row is wider than the
       width;
     - at width 20 the inline bar has at least 6 cells;
     - when the header's two parts collide, `context` is cut, never the
       figures;
     - legend entries are never split across rows, and an entry wider than
       the width is cut with `…`;
     - glyphs and colours: `█` used, `░` free, `▒` reserved and dimmed,
       each span carrying its row's `color`.
4. **Events, command and band.** `register.tsx` per the spec, and
   `register.test.tsx` covering every case in the spec's Verification list
   for it. The test's hooks answer `session.usage`, `store.get` and
   `store.set` as the spike settled. Drawing assertions loop over
   `['terminal', 'desktop'] as const`. Rules carried over from
   mermaid-ascii:
   - state refs are literals at the call site, because the engine refuses a
     ref built by a function;
   - the kit cannot reload a mod, so spec concern 5 (`epoch` across a
     reload) gets no test, and the plan records that;
   - the test answers `state.set` itself, as mermaid-ascii's cross-reload
     test did. It records every committed value in order, and it can hold a
     chosen write open on a promise the test releases. The held-write cases
     in the spec's Verification list (compaction, off, and a newer refresh,
     each during a held write) assert the commit order as well as the final
     band.

   Then mutation-check each guard, one at a time, and confirm each mutation
   fails at least one test:
   - the `agentId` skip on `turn.complete`;
   - the `agentId` and `precompute` skips on `session.compact`;
   - the clear before compaction;
   - the refresh after `{ skip }`;
   - the `epoch` comparison;
   - the epoch check moved out of the queue, back to before `publish`
     (the held-write cases catch this);
   - writing straight through, with no `publish` queue;
   - the bump on off;
   - not awaiting `refresh`;
   - `hasSurvey`;
   - the off check;
   - the `w < 20` step-aside;
   - `breakdown: 'summary'` (assert the stand-in was asked for `summary`).

   Finally run `claude plugin validate`, and `tsc` with the fallback
   tsconfig the spec describes, since the engine has not loaded the mod
   yet.
5. **Loading.** `env.CLAUDE_CODE_PLUGIN_DIRS` in `claude/.claude/settings.json`
   gains `:~/.claude/mods/context-bar`. This is a separate commit, because
   it changes every session on every machine.
6. **Docs.** The `CLAUDE.md` entry from "Files that change".

If implementation departs from this plan, update this file in the same
commit.

## After the merge (main checkout, not the worktree)

1. `stow -t ~ -R claude`.
2. Start a new session, using `claude --debug` the first time, to see the
   mod load and any skipped-hook lines. Once it has loaded, run `tsc -p` on
   the mod folder against the engine-written types.
3. Run `/context-bar`. The band appears straight away, from the refresh
   that turning it on starts.
4. Compare the band with `/context`. The figures should be close but not
   identical (spec concern 3).
5. Narrow the terminal across 60, 40 and 20 columns, and check each tier
   with no overflow.
6. Run `/compact`. The band disappears while the compaction runs and comes
   back with lower usage.
7. Answer the spec's concerns and record the findings in this file:
   - does `usage()` at `session.start` return used rows before the first
     reply (concern 1)?
   - do the theme colours draw on the terminal, and on desktop if it is in
     use (concern 2)?
   - does the band's height scroll acceptably (concern 4)?

## Risks

- **The mod API changes under the mod.** The types are this build's
  (2.1.309). `tsc -p` against the engine-written types catches drift on the
  next load, and the plugin tests catch behaviour drift. `reduce` is the one
  place the breakdown's shape is read, so a change lands there.
- **`settings.json` is written at runtime.** Claude Code writes `/config`
  and plugin changes through the symlink into the repo. Before step 5,
  `git diff claude/.claude/settings.json` must show nothing else. If it
  shows other changes, stop and ask Ben what to do with them: never stash,
  discard or commit them unasked. Then confirm with `git diff --cached`
  that the commit holds only the `CLAUDE_CODE_PLUGIN_DIRS` line.
- **The spike changes the design.** If step 1 fails, the spec changes
  first, in its own commit, before step 2.
- **Assertions that cannot fail.** Every test's stand-in for `usage()`
  records whether it was called. A "band hidden" assertion is paired with
  a check that it was drawn in the step before, so a band that never drew
  cannot pass as one that was hidden (see
  `docs/solutions/conventions/assertions-that-pass-when-they-cannot-check-2026-09-18.md`).

## Proof

- The spike's result (step 1) is written in this file.
- `claude plugin validate`, `tsc` and `claude plugin test` on the mod folder
  all pass, with the output pasted.
- The mutation check (step 4) lists each guard and the test that caught it.
- The live check (After the merge) shows the band and the narrow tiers, and
  records the answers to concerns 1, 2 and 4.
