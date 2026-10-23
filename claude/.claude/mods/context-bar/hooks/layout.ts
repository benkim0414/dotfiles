// Pure helpers for the band: no `$`, so every rule is tested without the
// engine. Rule numbers are the spec's (intent/show-context-breakdown/spec.md).

import type { ContextCategoryKind } from 'claude-code'

// R5: under 1000 as is, then k to one decimal (none from 10k), then M to
// two decimals, trailing zeros dropped. Integer rounding, so 9950 is 10k.
export function shortTokens(n: number): string {
  if (n < 1000) return String(Math.round(n))
  if (Math.round(n / 1000) < 1000) {
    const tenths = Math.round(n / 100)
    return tenths < 100 ? `${trim((tenths / 10).toFixed(1))}k` : `${Math.round(n / 1000)}k`
  }
  return `${trim((Math.round(n / 10_000) / 100).toFixed(2))}M`
}

const trim = (s: string) => s.replace(/\.?0+$/, '')

// R5: whole percent of the window; any non-zero share is at least 1%.
export function percent(tokens: number, window: number): string {
  if (tokens <= 0 || window <= 0) return '0%'
  return `${Math.max(1, Math.round((tokens / window) * 100))}%`
}

const LABELS: Record<string, string> = {
  'System prompt': 'system prompt',
  'System tools': 'tools',
  'MCP tools': 'mcp tools',
  'Custom agents': 'agents',
  'Memory files': 'memory files',
  Skills: 'skills',
  Messages: 'messages',
}

// R5: by kind first; a used row through the map, else its name lowercased.
export function labelFor(row: { name: string; kind: ContextCategoryKind }): string {
  if (row.kind === 'free') return 'free'
  if (row.kind === 'buffer') return 'reserved'
  return LABELS[row.name] ?? row.name.toLowerCase()
}

// R3: share `width` cells among parts in bar order. When no part has tokens
// the whole bar goes to `fill` (the free part).
export function apportion(tokens: number[], width: number, fill: number): number[] {
  const d = tokens.reduce((a, b) => a + b, 0)
  if (d <= 0) return tokens.map((_, i) => (i === fill ? width : 0))

  const parts = tokens.map((t, i) => {
    const exact = (t * width) / d
    return { i, t, cells: 0, floor: Math.floor(exact), remainder: exact - Math.floor(exact) }
  })
  const nonZero = parts.filter(p => p.t > 0)

  // Step 3, crowded: the `width` largest parts (ties: earlier) get one each.
  if (nonZero.length > width) {
    const chosen = [...nonZero].sort((a, b) => b.t - a.t || a.i - b.i).slice(0, width)
    for (const p of chosen) p.cells = 1
    return parts.map(p => p.cells)
  }

  // Step 2: largest remainder; remainder ties go to the earlier part.
  for (const p of parts) p.cells = p.floor
  let left = width - parts.reduce((a, p) => a + p.cells, 0)
  for (const p of [...nonZero].sort((a, b) => b.remainder - a.remainder || a.i - b.i)) {
    if (left === 0) break
    p.cells++
    left--
  }

  // Step 3: a part with tokens and no cell takes one from the part with the
  // most cells (ties: the later), which has at least 2 since k ≤ width.
  for (const p of nonZero) {
    if (p.cells > 0) continue
    const donor = parts.reduce((most, q) => (q.cells >= most.cells ? q : most))
    donor.cells--
    p.cells = 1
  }
  return parts.map(p => p.cells)
}
