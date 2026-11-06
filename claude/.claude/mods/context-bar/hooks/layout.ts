// Pure helpers for the band: no `$`, so every rule is tested without the
// engine. Rule numbers are the spec's (intent/show-context-breakdown/spec.md).

import type { ContextCategory, ContextCategoryKind, SessionUsage } from 'claude-code'

import type { Part, Reading } from '../types'

// One run of text in a row; the render hook draws each as a <Text>.
export type Span = { text: string; color?: string; dim?: boolean; bold?: boolean; background?: string }
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
  return {
    used,
    free: free ? part(free) : { label: 'free', tokens: 0, color: 'inactive' },
    reserved: buffer ? part(buffer) : null,
    totalTokens: b.totalTokens,
    window,
    compactsAt: b.isAutoCompactEnabled ? (b.autoCompactThreshold ?? null) : null,
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
export function spread(left: Row, right: Row, width: number): Row {
  const r = cutRow(right, width)
  const l = cutRow(left, width - widthOf(r) - 1)
  const gap = width - widthOf(l) - widthOf(r)
  return [...l, ...(gap > 0 ? [{ text: ' '.repeat(gap) }] : []), ...r]
}

// R6: the share of the window in use, on green, yellow from 70%, red from 90%.
function badge(totalTokens: number, window: number): Span {
  const pct = percent(totalTokens, window)
  const n = Number.parseInt(pct, 10)
  const background = n >= 90 ? 'error' : n >= 70 ? 'warning' : 'success'
  return { text: ` ${pct} `, color: 'inverseText', background }
}

// The band: its rows, and whether they sit in the frame (R7).
export type Band = { rows: Row[]; isFramed: boolean }

// The frame's border and padding take two columns each side.
const FRAME = 4

// R1, R4–R7: the band at `width` columns, or null to step aside.
export function layout(reading: Reading, width: number): Band | null {
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

  // R3, R4: one glyph per cell, each part in its row's colour; the reserve
  // opens with the compaction marker.
  const bar = (cells: number): Row => {
    const parts = [...used, free, ...(reserved ? [reserved] : [])]
    const counts = apportion(parts.map(p => p.tokens), cells, used.length)
    const spans: Row = []
    parts.forEach((p, i) => {
      const n = counts[i] ?? 0
      if (n === 0) return
      if (i < used.length) spans.push({ text: '█'.repeat(n), color: p.color })
      else if (p === free) spans.push({ text: '░'.repeat(n), color: p.color })
      else {
        spans.push({ text: '│', color: 'warning' })
        if (n > 1) spans.push({ text: '░'.repeat(n - 1), color: p.color, dim: true })
      }
    })
    return spans
  }

  const mark: Span = { text: '◆', color: 'claude' }
  if (width < 40) {
    const prefix = ` ${u}/${w} `
    return { rows: [[mark, { text: prefix }, ...bar(width - 1 - prefix.length)]], isFramed: false }
  }
  const left: Row = [mark, { text: ' context', bold: true }]
  const share = badge(totalTokens, window)
  if (width < 60) {
    const right: Row = [{ text: `${u}/${w}`, bold: true }, { text: ' ' }, share]
    return { rows: [spread(left, right, width), bar(width)], isFramed: false }
  }

  const room = width - FRAME
  const context = ` of ${w}` + (compactsAt === null ? '' : ` · compacts at ${shortTokens(compactsAt)}`)
  const right: Row = [{ text: u, bold: true }, { text: context, dim: true }, { text: ' ' }, share]
  const entries: Row[] = [...used.map(p => entry(p, percent(p.tokens, window))), entry(free, null)]
  return { rows: [spread(left, right, room), bar(room), ...wrap(entries, room)], isFramed: true }
}

// R18: the desktop's palette tokens the context panel's chart uses, named
// as the desktop names them (`--cds-<name>`), with the values its colour
// theme gives them. A mod cannot name them: the desktop resolves a Claude
// Code theme key, a hex or rgb()/hsl() value or an ANSI name, and none of
// its theme keys maps to a chart colour; the bar's SVG is drawn as an
// image, which reads no CSS variable. Hence the values, kept by name here.
export const CDS = {
  'blue-400': '#338ced',
  'orange-400': '#e76624',
  'aqua-400': '#00a888',
  'yellow-350': '#d28e05',
  'magenta-400': '#e24d8b',
  'gray-350': '#959595',
  'gray-550': '#5e5e5e',
} as const

// The panel's chart roles in dark mode (`--cds-chart-<role>`).
export const CHART = {
  categorical: [CDS['blue-400'], CDS['orange-400'], CDS['aqua-400'], CDS['yellow-350'], CDS['magenta-400']],
  // "Other" rows.
  reference: CDS['gray-350'],
  // The buffer.
  muted: CDS['gray-550'],
  // The track and free: `reference` at 15%.
  referenceTint: { color: CDS['gray-350'], opacity: 0.15 },
} as const

// As the desktop panel: at most this many series in the bar, the buffer
// counted; past it, the smallest used rows share one "other" part.
const SERIES = 6

// The bar's height in CSS pixels, and the width taken per cell of
// `bodyColumns` to size the drawing (the code font's advance, rounded up).
const THICK = 8
const CELL = 8

// The band on a surface that lays out in pixels (R18): the header's two
// sides, the bar as SVG markup and the legend's entries. The surface
// spreads the header, scales the bar and wraps the legend.
export type FlexBand = { left: Row; right: Row; bar: string; alt: string; legend: Row[]; isFramed: boolean }

const r2 = (n: number) => Math.round(n * 100) / 100

// One rectangle with its own left and right corner radii.
function pill(x: number, w: number, h: number, rs: number, re: number, fill: string): string {
  const a = Math.min(rs, w / 2, h / 2)
  const b = Math.min(re, w / 2, h / 2)
  return (
    `<path fill="${fill}" d="M${r2(x + a)} 0H${r2(x + w - b)}A${b} ${b} 0 0 1 ${r2(x + w)} ${b}` +
    `V${h - b}A${b} ${b} 0 0 1 ${r2(x + w - b)} ${h}H${r2(x + a)}A${a} ${a} 0 0 1 ${r2(x)} ${h - a}` +
    `V${a}A${a} ${a} 0 0 1 ${r2(x + a)} 0Z"/>`
  )
}

// R18: the same figures as `layout`, at the same widths, drawn as the
// desktop's context panel draws its bar.
export function flexLayout(reading: Reading, width: number): FlexBand | null {
  if (width < 20) return null
  const { window, totalTokens, compactsAt } = reading
  const isOver = totalTokens > window
  const free: Part = { ...reading.free, tokens: isOver ? 0 : reading.free.tokens }
  const reserved = reading.reserved && { ...reading.reserved, tokens: isOver ? 0 : reading.reserved.tokens }
  const u = shortTokens(totalTokens)
  const w = shortTokens(window)
  const isFramed = width >= 60

  // Theme keys, as on the terminal: the desktop maps each to its own colour.
  const left: Row = [{ text: '◆', color: 'claude' }, { text: ' context', bold: true }]
  const pct = percent(totalTokens, window)
  const share: Span = { ...badge(totalTokens, window), bold: true }
  const context = ` of ${w}` + (compactsAt === null ? '' : ` · compacts at ${shortTokens(compactsAt)}`)
  const right: Row = isFramed
    ? [{ text: u, bold: true }, { text: context, dim: true }, { text: ' ' }, share]
    : [{ text: `${u}/${w}`, bold: true }, { text: ' ' }, share]

  // Used rows largest first. With more series than SERIES, the first
  // 5 less the buffer keep a colour and the rest share `other`.
  const used = reading.used.filter(p => p.tokens > 0).sort((a, b) => b.tokens - a.tokens)
  const buffer = reserved !== null && reserved.tokens > 0 ? reserved : null
  const isCrowded = used.length + (buffer ? 1 : 0) > SERIES
  const kept = isCrowded ? 5 - (buffer ? 1 : 0) : used.length
  const colored = used.map((p, i) => ({
    ...p,
    color: i < kept ? (CHART.categorical[i] ?? CHART.reference) : CHART.reference,
  }))
  const rest = colored.slice(kept).reduce((a, p) => a + p.tokens, 0)
  const parts = [
    ...colored.slice(0, kept).map(p => ({ tokens: p.tokens, color: p.color })),
    ...(rest > 0 ? [{ tokens: rest, color: CHART.reference }] : []),
    ...(buffer ? [{ tokens: buffer.tokens, color: CHART.muted }] : []),
  ]

  // The bar: a pill-shaped track, then the parts from the left, each at
  // least 2px and 1px apart, the run's two ends round and its seams 2px.
  const px = Math.max(40, (isFramed ? width - FRAME : width) * CELL)
  const total = Math.max(window, parts.reduce((a, p) => a + p.tokens, 0) + free.tokens) || 1
  const shapes: string[] = []
  let x = 0
  parts.forEach((p, i) => {
    const seam = i === 0 ? 0 : 1
    const span = Math.max(2 + seam, (p.tokens / total) * px)
    const isLast = i === parts.length - 1
    shapes.push(pill(x + seam, span - seam, THICK, i === 0 ? THICK / 2 : 2, isLast ? THICK / 2 : 2, p.color))
    x += span
  })
  const bar =
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${px} ${THICK}" width="${px}" height="${THICK}">` +
    `<rect width="${px}" height="${THICK}" rx="${THICK / 2}" fill="${CHART.referenceTint.color}" fill-opacity="${CHART.referenceTint.opacity}"/>` +
    `${shapes.join('')}</svg>`
  const alt = `context ${u} of ${w}, ${pct} used`

  // The legend in the bar's order: used, the buffer, then free.
  const legend = isFramed
    ? [
        ...colored.map(p => entry(p, percent(p.tokens, window))),
        ...(buffer ? [entry({ ...buffer, color: CHART.muted }, percent(buffer.tokens, window))] : []),
        entry({ ...free, color: CHART.referenceTint.color }, null),
      ]
    : []
  return { left, right, bar, alt, legend, isFramed }
}

// R5: `■ <label> <tokens> <pct>`, the swatch coloured, the tokens bold and
// the percent dim; the free entry is dim throughout, with no percent.
function entry(p: Part, pct: string | null): Row {
  const swatch: Span = { text: '■', color: p.color }
  if (pct === null) return [swatch, { text: ` ${p.label} ${shortTokens(p.tokens)}`, dim: true }]
  return [
    swatch,
    { text: ` ${p.label} ` },
    { text: shortTokens(p.tokens), bold: true },
    { text: ' ' },
    { text: pct, dim: true },
  ]
}

const widthOf = (r: Row) => r.reduce((a, s) => a + s.text.length, 0)

// Cut a row to `n` columns ending in …, which takes the last column even
// when the cut falls between two spans.
function cutRow(r: Row, n: number): Row {
  if (widthOf(r) <= n) return r
  if (n <= 0) return []
  const out: Row = []
  let room = n - 1
  for (const s of r) {
    if (room <= 0) break
    const text = s.text.slice(0, room)
    out.push({ ...s, text })
    room -= text.length
  }
  const last = out.at(-1)
  if (last) last.text += '…'
  else out.push({ text: '…' })
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
