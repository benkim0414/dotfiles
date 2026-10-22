# Intent: mermaid-ascii mod
Author: Ben Kim. Status: draft.

## Problem

The `show-me` skill explains concepts visually, and for interaction, control
flow and data flow it writes ```` ```mermaid ```` fences. The Claude Code
terminal transcript draws those fences as raw Mermaid source, so to see the
diagram you have to read the source or paste it into a renderer.

## Proposed outcome

A Claude Code mod redraws every ```` ```mermaid ```` block in an assistant
reply as text art, in place, in the terminal transcript.

- The art replaces the Mermaid source in the drawing.
- When conversion fails, the diagram type is unsupported, or the art is wider
  than the terminal, the original block is shown unchanged.
- The stored message is never changed: ctrl+o and the transcript file keep the
  Mermaid source, and the model still sees it.

## Affected users and systems

- **The person reading the transcript:** sees diagrams instead of source.
- **The `show-me` skill:** unchanged. The mod reacts to any mermaid fence, from
  any skill or reply.
- **Claude Code:** a `ui.render` hook on `AssistantMessage`, terminal surface
  only. Other surfaces draw Mermaid natively and are left alone.

## Constraints

- **Converter: beautiful-mermaid** (npm, pinned version, `renderMermaidASCII`).
  The Mermaid team ships no ASCII renderer: the official
  `@mermaid-js/mermaid-cli` (`mmdc`) writes only SVG, PNG or PDF. beautiful-mermaid
  is a TypeScript port of Alexander Grooff's mermaid-ascii and was chosen over
  the Go original and mermaid2term because it runs on the installed bun/node
  and covers the most diagram types (flowchart, sequence, class, ER, xychart).
  It does not cover state diagrams; those fall back to source.
- **Display only.** The mod rewrites the drawing, never the stored message or
  the model's context.
- **Never blocks drawing.** Conversion runs outside the render hook. Results
  are cached per block, failures included, so a redraw never re-runs a failed
  conversion.
- **Unicode box drawing** by default (the library's default charset).
- **Lives in dotfiles.** It ships in the `claude` Stow package under
  `claude/.claude/mods/`, so every machine gets it via `stow -t ~ claude`.

## Open questions

- How the mod is loaded from `~/.claude/mods/` on each machine
  (`CLAUDE_CODE_PLUGIN_DIRS`, `--plugin-dir`, or a marketplace entry), and
  whether `claude-sync` should wire it.
- Where `beautiful-mermaid` is installed: a `package.json` beside the mod
  (`bun install` once per machine) or a global install. `node_modules` must
  not be committed or stowed.

## Later changes (each gets its own intent)

- A pure-ASCII charset option (`userConfig`), for terminals or logs without
  box-drawing glyphs.
- A ctrl+o-style toggle to show the source and the art together.

## Background

- [beautiful-mermaid on npm](https://www.npmjs.com/package/beautiful-mermaid)
- [mermaid-ascii (Go)](https://pkg.go.dev/github.com/pgavlin/mermaid-ascii)
- [mermaid2term](https://github.com/watzon/mermaid2term)
- The `show-me` skill: `~/.claude/skills/show-me/SKILL.md`
