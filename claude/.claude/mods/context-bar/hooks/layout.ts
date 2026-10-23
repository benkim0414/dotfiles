// Pure helpers for the band: no `$`, so every rule is tested without the
// engine. Rule numbers are the spec's (intent/show-context-breakdown/spec.md).

import type { ContextCategory, ContextCategoryKind, SessionUsage } from 'claude-code'

import type { Part, Reading } from '../types'

// One run of text in a row; the render hook draws each as a <Text>.
export type Span = { text: string; color?: string; dim?: boolean }
export type Row = Span[]

const SEP = '  '

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

// R2, R10: the breakdown reduced to what the layout needs, by kind; null
// when there is no breakdown or no used row.
export function reduce(usage: SessionUsage): Reading | null {
  const b = usage.context.breakdown
  if (!b) return null
  const part = (c: ContextCategory): Part => ({ label: labelFor(c), tokens: c.tokens, color: c.color })
  const used = b.categories.filter(c => c.kind === 'used').map(part)
  if (used.length === 0) return null
  const free = b.categories.find(c => c.kind === 'free')
  const buffer = b.categories.find(c => c.kind === 'buffer')
  const window = b.rawMaxTokens
  const threshold = b.isAutoCompactEnabled && window > 0 ? b.autoCompactThreshold : undefined
  return {
    used,
    free: free ? part(free) : { label: 'free', tokens: 0, color: 'inactive' },
    reserved: buffer ? part(buffer) : null,
    totalTokens: b.totalTokens,
    window,
    compactsAt: threshold === undefined ? null : Math.round((threshold / window) * 100),
  }
}

// R7: cut text to `n` columns, ending in … when anything was cut.
function cut(s: string, n: number): string {
  if (s.length <= n) return s
  if (n <= 0) return ''
  return s.slice(0, n - 1) + '…'
}

// R7: left and right parts with at least one space between; when both do
// not fit, the right part wins and the left is cut.
export function spread(left: string, right: string, width: number): Row {
  const r = cut(right, width)
  const l = cut(left, width - r.length - 1)
  return [{ text: l + ' '.repeat(width - l.length - r.length) + r }]
}

// R1, R4–R7: the band's rows at `width` columns, or null to step aside.
export function layout(reading: Reading, width: number): Row[] | null {
  if (width < 20) return null
  const { used, window, totalTokens, compactsAt } = reading
  // R2: over the window, free and reserved show 0.
  const isOver = totalTokens > window
  const free: Part = { ...reading.free, tokens: isOver ? 0 : reading.free.tokens }
  const reserved: Part | null = reading.reserved && {
    ...reading.reserved,
    tokens: isOver ? 0 : reading.reserved.tokens,
  }
  const u = shortTokens(totalTokens)
  const w = shortTokens(window)

  // R3, R4: one glyph per cell, each part in its row's colour.
  const bar = (cells: number): Row => {
    const parts = [...used, free, ...(reserved ? [reserved] : [])]
    const counts = apportion(parts.map(p => p.tokens), cells, used.length)
    const spans: Row = []
    parts.forEach((p, i) => {
      const n = counts[i] ?? 0
      if (n === 0) return
      if (i < used.length) spans.push({ text: '█'.repeat(n), color: p.color })
      else if (p === free) spans.push({ text: '░'.repeat(n), color: p.color })
      else spans.push({ text: '▒'.repeat(n), color: p.color, dim: true })
    })
    return spans
  }

  if (width < 40) {
    const prefix = `◆ ${u}/${w} `
    return [[{ text: prefix }, ...bar(width - prefix.length)]]
  }
  if (width < 60) {
    const right = `${u}/${w}` + (compactsAt === null ? '' : ` · ${compactsAt}%`)
    return [spread('◆ context', right, width), bar(width)]
  }

  const right = `${u} of ${w}` + (compactsAt === null ? '' : ` · compacts at ${compactsAt}%`)
  const entries: Row[] = [
    ...used.map(p => entry(p, percent(p.tokens, window))),
    entry(free, null),
    ...(reserved && reserved.tokens > 0 ? [entry(reserved, percent(reserved.tokens, window))] : []),
  ]
  return [spread('◆ context', right, width), bar(width), ...wrap(entries, width)]
}

// R5: `■ <label> <tokens> <pct>`, the swatch coloured and the percent dim;
// the free entry has no percent.
function entry(p: Part, pct: string | null): Row {
  const words = `${p.label} ${shortTokens(p.tokens)}`
  if (pct === null) return [{ text: '■', color: p.color }, { text: ` ${words}` }]
  return [{ text: '■', color: p.color }, { text: ` ${words} ` }, { text: pct, dim: true }]
}

const widthOf = (r: Row) => r.reduce((a, s) => a + s.text.length, 0)

// Cut a row to `n` columns; the span where it is cut ends in …
function cutRow(r: Row, n: number): Row {
  if (widthOf(r) <= n) return r
  const out: Row = []
  let room = n
  for (const s of r) {
    if (room <= 0) break
    out.push({ ...s, text: cut(s.text, room) })
    room -= s.text.length
  }
  return out
}

// R5, R7: pack whole entries into rows of at most `width`, two spaces apart.
function wrap(entries: Row[], width: number): Row[] {
  const rows: Row[] = []
  let current: Row = []
  for (const e of entries.map(e => cutRow(e, width))) {
    if (current.length > 0 && widthOf(current) + SEP.length + widthOf(e) <= width) {
      current.push({ text: SEP }, ...e)
    } else {
      if (current.length > 0) rows.push(current)
      current = [...e]
    }
  }
  if (current.length > 0) rows.push(current)
  return rows
}
