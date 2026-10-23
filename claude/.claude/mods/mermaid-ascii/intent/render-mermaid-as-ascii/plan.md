# Plan: mermaid-ascii mod
From: [spec.md](spec.md). Status: draft.

## Files that change

Paths are relative to the `claude/` package, except the last two, which
are at the repo root.

- `.claude/mods/mermaid-ascii/.claude-plugin/plugin.json`: `name`
  `mermaid-ascii`, `version` `0.1.0`, a one-line `description`, `types`
  `./types/index.d.ts`
- `.claude/mods/mermaid-ascii/hooks/hooks.json`:
  `{ "modules": ["./register.tsx"] }`
- `.claude/mods/mermaid-ascii/hooks/text.ts`: pure helpers with no `$`:
  - `scanFences(text)`: top-level fenced blocks with their info string,
    source and line span; nested fences stay literal (R1);
  - `displayWidth(line)`: columns per R2's rules;
  - `fenceFor(art)`: `max(3, longest backtick run + 1)` backticks;
  - `fnv1a32(source)`: the state member id.
- `.claude/mods/mermaid-ascii/hooks/register.tsx`: the `ui.render` hook on
  `AssistantMessage`, `convert`, and the toast (R1–R8)
- `.claude/mods/mermaid-ascii/hooks/text.test.ts` and
  `hooks/register.test.tsx`: `claude plugin test` suites
- `.claude/mods/mermaid-ascii/types/index.d.ts`: the `PluginState` contract
  from the spec
- `.claude/mods/mermaid-ascii/tsconfig.json`: extends the
  `.claude-plugin/types/tsconfig.json` the engine writes on load
- `.claude/mods/mermaid-ascii/render/package.json`,
  `render/package-lock.json`: `beautiful-mermaid` at exactly `1.1.3`,
  `"type": "module"`, `"private": true`
- `.claude/mods/mermaid-ascii/render/render.mjs`: stdin to stdout, exit
  codes 0, 1 and 3 as the spec's table
- `.claude/tests/mermaid-ascii/run.sh`: the converter and Stow suite
- `.stow-local-ignore`: new. Stow's default list restated (`RCS`, `.+,v`,
  `CVS`, `\.\#.+`, `\.cvsignore`, `\.svn`, `_darcs`, `\.hg`, `\.git`,
  `\.gitignore`, `\.gitmodules`, `.+~`, `\#.*\#`, `^/README.*`,
  `^/LICENSE.*`, `^/COPYING`) plus
  `^/\.claude/mods/[^/]+/render/node_modules$` (R10)
- `.claude/settings.json`: `env.CLAUDE_CODE_PLUGIN_DIRS` set to
  `~/.claude/mods/mermaid-ascii` (R9)
- `.gitignore` (repo root):
  - `claude/.claude/mods/*/render/node_modules/`;
  - `claude/.claude/mods/*/.claude-plugin/types/`, which the engine writes
    into every loaded mod and which would otherwise dirty the tree
- `CLAUDE.md` (repo root): a short "Mods" section with the `npm ci` step
  and the Stow ignore, next to the other Stow gotchas

## Order of work

Each step is one commit, test first where there is a test to write. The
work happens in this worktree; stow and live checks wait for the merge.

1. **Spike: scheduling from a render hook** (spec "Areas of concern" 2).
   A throwaway mod at `.spike/clock-after/` in this worktree's root:
   outside the `claude` package, so Stow never sees it, and never staged.
   It has a `ui.render` hook on `AssistantMessage` that calls
   `$.clock.after(0, …)`, whose callback does `$.state.set`, plus a
   `claude plugin test .spike/clock-after` run that mounts the component
   and expects the redraw. The test kit runs it from its path, so nothing
   loads it into a session. Delete the folder when the step ends.
   - It passes: keep the spec's design.
   - It fails: convert from `turn.complete` instead, update the spec's
     Conversion section and R5, and note that resumed transcripts draw
     source until redrawn.

   Record the result in this file under step 1. No commit in the repo
   unless the spec changes.

   **Result (2026-10-23): passes.** The hook read the member, scheduled
   `$.clock.after(0, …)` and returned `next(e)`; after `mock.clock(on)`'s
   `settle()` the mounted `AssistantMessage` drew the written value with no
   `$.ui.invalidate`. With the write removed the same test failed
   (`Expected: "CONVERTED"`, `Received: "SOURCE"`), so it was checking. The
   spec's design stands. `claude plugin validate` also refused the spike's
   contract for an `import` line: `types/index.d.ts` must be self-contained,
   naming `StateFamily` inside `declare module 'claude-code'` without
   importing it.
2. **Converter.** `render/package.json`, `npm install` to produce the lock
   file, `render.mjs`, and the `.gitignore` entry for `node_modules`. Then
   `run.sh`, converter half, with assertions that cannot pass silently (see
   `docs/solutions/conventions/assertions-that-pass-when-they-cannot-check-2026-09-18.md`):
   - flowchart, sequence and state fixtures exit 0, and stdout is non-empty,
     holds at least one box-drawing character (`─`, `│`, `┌`) and no `\x1b`;
   - an invalid diagram exits exactly 1 with empty stdout;
   - a copy of `render.mjs` in an empty `mktemp -d` directory, with
     `NODE_PATH` unset, exits exactly 3;
   - the suite exits 2, not 0, when `node` is missing or `npm ci` has not
     run, so "could not check" never reads as "passed".
3. **Stow exclusion.** `claude/.stow-local-ignore`, and `run.sh`'s Stow
   half. Stow folds a missing target directory into one link: an empty
   temp home only ever shows `LINK: .claude => …` (confirmed by the plan
   review), so it proves nothing about `node_modules` and is not used.
   Descent into a pre-created real directory was confirmed with a dry run
   on 2026-10-23: it linked the files inside it and folded the rest. Each
   check below captures Stow's exit status and fails on non-zero before
   reading its output.
   - **`node_modules` excluded.** With `render/node_modules` present, dry-run
     into a temp home where `.claude/mods/mermaid-ascii/render/` is a real
     directory. Assert the output names `render.mjs` (it reached the
     directory) and names no path containing `node_modules`.
   - **Stow's defaults still apply.** The new file replaces Stow's default
     list, so build an isolated fixture package in `mktemp -d`, not the
     real `claude` package: `pkg/.claude/mods/x/render/keep.txt` and
     `pkg/.claude/mods/x/render/notes.txt~` (a backup file, covered by the
     default `.+~` pattern), with a copy of `claude/.stow-local-ignore`.
     Dry-run into a home with `.claude/mods/x/render/` pre-created. Assert
     `keep.txt` is named (it reached the directory) and `notes.txt~` is
     not.
   - **The defaults check can fail.** Run the same fixture again with the
     `.+~` line removed from its copy of the ignore file, and assert
     `notes.txt~` is now named. If it is not, the previous assertion was
     not testing anything and the suite fails.
4. **Mod scaffold and pure helpers.** `plugin.json`, `hooks.json`,
   `types/index.d.ts`, `tsconfig.json`, the `.claude-plugin/types/`
   ignore, and `text.ts` with `text.test.ts`, written first:
   - `scanFences`: backtick and tilde fences, `Mermaid` and `mermaid  `
     info strings, an unclosed fence, two fences in one reply, a mermaid
     fence inside a four-backtick markdown fence (not returned), a closing
     fence longer than the opening one;
   - `displayWidth`: ASCII, box drawing (1 each), CJK (2 each), an emoji
     with a ZWJ sequence, a tab at columns 0 and 3;
   - `fenceFor`: art with no backticks, a run of one, a run of four;
   - `fnv1a32`: a fixed known vector.

   `register.tsx` is a stub that returns `next(e)`.
5. **Render hook and conversion.** `register.tsx` per the spec, and
   `register.test.tsx` with `process.run` stubbed by the test's own hook,
   covering every case in the spec's Verification list. The collision cases
   stub the id function through a module-level seam in `text.ts`, not by
   searching for real FNV collisions. The process stub holds each
   conversion open on a promise the test resolves, so the test can draw A
   and B before either finishes and settle them in a chosen order. Tests
   for the same-source and cross-reload cases follow the spec's
   claim-then-keep-first ownership rule (Render hook, steps 4 and 5). Loop the drawing assertions over
   `['terminal', 'desktop'] as const`, expecting the rewrite only on
   `terminal`. Then `claude plugin validate` and `tsc -p` on the folder.
6. **Loading.** `env.CLAUDE_CODE_PLUGIN_DIRS` in `claude/.claude/settings.json`,
   merged into the existing `env` block (it holds `DISABLE_COST_WARNINGS`).
   Separate commit, because it changes every session on every machine.
7. **Docs.** The CLAUDE.md section from "Files that change".

If implementation departs from this plan, update this file in the same
commit.

## After the merge (main checkout, not the worktree)

1. `npm ci --prefix ~/workspace/dotfiles/claude/.claude/mods/mermaid-ascii/render`
2. `stow -t ~ -R claude`
3. New session; `claude --debug` the first time, to see the mod load and any
   skipped-hook lines.
4. `/show-me` on a topic that yields a sequence diagram and on one that
   yields a flowchart; check the art draws and fits.
5. Answer the spec's open concerns and record them in this file:
   - ctrl+o (concern 1): source or art;
   - the reply indent the width check assumes (concern 4);
   - the desktop app finding `node` (concern 3), if the desktop app is in
     use.

## Risks

- **The mod API changes under the mod.** The types are this build's
  (2.1.309). `tsc -p` against the engine-written types catches drift on
  the next load; the plugin tests catch behaviour drift.
- **Stow's default ignore list differs by version.** The restated list is
  Stow 2.x's. Step 3's test checks the defaults that matter here still
  hold, rather than trusting the list.
- **`settings.json` is written at runtime.** Claude Code writes `/config`
  and plugin changes through the symlink into the repo. Before step 6,
  `git diff claude/.claude/settings.json` must show nothing else. If it
  shows other changes, stop and ask Ben what to do with them: never stash,
  discard or commit them unasked. Then confirm with `git diff --cached`
  that the commit holds only the `env` line.
- **The library emits something the terminal mangles.** `colorMode: 'none'`
  covers ANSI codes; the converter test asserts no `ESC` byte reaches
  stdout.

## Proof

- `claude/.claude/tests/mermaid-ascii/run.sh` exits 0, output pasted.
- `claude plugin validate`, `tsc -p` and `claude plugin test` on the mod
  folder all pass, output pasted.
- The spike's result (step 1) is written in this file.
- The live check (After the merge, step 4) shows a sequence diagram drawn
  as art, with the ctrl+o and indent findings recorded.
