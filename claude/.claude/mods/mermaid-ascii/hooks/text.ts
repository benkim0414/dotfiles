// Pure text helpers for the render hook: no `$`, so they test on their own.

export type Fence = {
  // Everything after the opening run, as written.
  info: string
  // The opening fence's indent, removed from each source line.
  indent: string
  source: string
  // Line indexes of the opening and closing fence lines.
  start: number
  end: number
}

const OPEN = /^( {0,3})(`{3,}|~{3,})(.*)$/
const CLOSE = /^ {0,3}(`{3,}|~{3,})[ \t]*$/

// Top-level fenced code blocks that are closed (R1). A fence inside another
// fence is part of that fence's source, so it is never returned on its own.
export function scanFences(text: string): Fence[] {
  // A CRLF reply's lines keep a trailing CR; it is dropped before matching,
  // so line indexes still count the reply's own lines.
  const lines = text.split('\n').map(l => (l.endsWith('\r') ? l.slice(0, -1) : l))
  const found: Fence[] = []
  let open: { run: string; indent: string; info: string; start: number } | undefined

  lines.forEach((line, i) => {
    if (!open) {
      const m = OPEN.exec(line)
      if (!m) return
      const [, indent = '', run = '', info = ''] = m
      // A backtick fence's info string may not hold a backtick.
      if (!(run.startsWith('`') && info.includes('`'))) open = { indent, run, info, start: i }
      return
    }
    const run = CLOSE.exec(line)?.[1]
    if (run && run[0] === open.run[0] && run.length >= open.run.length) {
      const body = lines.slice(open.start + 1, i).map(l => dedent(l, open!.indent.length))
      found.push({ info: open.info, indent: open.indent, source: body.join('\n'), start: open.start, end: i })
      open = undefined
    }
  })
  return found
}

function dedent(line: string, n: number): string {
  let k = 0
  while (k < n && line[k] === ' ') k++
  return line.slice(k)
}

export function isMermaid(info: string): boolean {
  return info.trim().toLowerCase() === 'mermaid'
}

// Code point ranges a terminal draws two columns wide: East Asian Wide and
// Fullwidth, and emoji drawn as pictures.
const WIDE: [number, number][] = [
  [0x1100, 0x115f], [0x231a, 0x231b], [0x2329, 0x232a], [0x23e9, 0x23ec],
  [0x23f0, 0x23f0], [0x23f3, 0x23f3], [0x25fd, 0x25fe], [0x2614, 0x2615],
  [0x2648, 0x2653], [0x267f, 0x267f], [0x2693, 0x2693], [0x26a1, 0x26a1],
  [0x26aa, 0x26ab], [0x26bd, 0x26be], [0x26c4, 0x26c5], [0x26ce, 0x26ce],
  [0x26d4, 0x26d4], [0x26ea, 0x26ea], [0x26f2, 0x26f3], [0x26f5, 0x26f5],
  [0x26fa, 0x26fa], [0x26fd, 0x26fd], [0x2705, 0x2705], [0x270a, 0x270b],
  [0x2728, 0x2728], [0x274c, 0x274c], [0x274e, 0x274e], [0x2753, 0x2755],
  [0x2757, 0x2757], [0x2795, 0x2797], [0x27b0, 0x27b0], [0x27bf, 0x27bf],
  [0x2b1b, 0x2b1c], [0x2b50, 0x2b50], [0x2b55, 0x2b55], [0x2e80, 0x303e],
  [0x3041, 0x33ff], [0x3400, 0x4dbf], [0x4e00, 0x9fff], [0xa000, 0xa4cf],
  [0xa960, 0xa97f], [0xac00, 0xd7a3], [0xf900, 0xfaff], [0xfe10, 0xfe19],
  [0xfe30, 0xfe6f], [0xff00, 0xff60], [0xffe0, 0xffe6], [0x16fe0, 0x16fe4],
  [0x17000, 0x18cff], [0x1b000, 0x1b2ff], [0x1f004, 0x1f004], [0x1f0cf, 0x1f0cf],
  [0x1f18e, 0x1f18e], [0x1f191, 0x1f19a], [0x1f200, 0x1f251], [0x1f300, 0x1f64f],
  [0x1f680, 0x1f6ff], [0x1f7e0, 0x1f7eb], [0x1f90c, 0x1f9ff], [0x1fa70, 0x1faff],
  [0x20000, 0x2fffd], [0x30000, 0x3fffd],
]

// Combining marks, zero-width spaces and joiners, variation selectors.
const ZERO: [number, number][] = [
  [0x0300, 0x036f], [0x0483, 0x0489], [0x0591, 0x05bd], [0x0610, 0x061a],
  [0x064b, 0x065f], [0x1ab0, 0x1aff], [0x1dc0, 0x1dff], [0x200b, 0x200f],
  [0x20d0, 0x20ff], [0x3099, 0x309a], [0xfe00, 0xfe0f], [0xfe20, 0xfe2f],
  [0x1f3fb, 0x1f3ff], [0xe0000, 0xe007f], [0xe0100, 0xe01ef],
]

const ZWJ = 0x200d

function inRanges(cp: number, ranges: [number, number][]): boolean {
  let lo = 0
  let hi = ranges.length - 1
  while (lo <= hi) {
    const mid = (lo + hi) >> 1
    const [from, to] = ranges[mid]!
    if (cp < from) hi = mid - 1
    else if (cp > to) lo = mid + 1
    else return true
  }
  return false
}

// Columns a line takes in the terminal (R2). A code point after a zero-width
// joiner continues the glyph before it, so an emoji ZWJ sequence counts once.
export function displayWidth(line: string): number {
  let col = 0
  let joined = false
  for (const ch of line) {
    const cp = ch.codePointAt(0)!
    if (cp === 0x09) col += 8 - (col % 8)
    else if (cp === ZWJ) { joined = true; continue }
    else if (joined || inRanges(cp, ZERO)) { /* zero width */ }
    else col += inRanges(cp, WIDE) ? 2 : 1
    joined = false
  }
  return col
}

// Message text may hold no control character but tab and newline (R7): the
// engine skips a hook whose rewrite holds one. C0, DEL and C1.
export function hasForbiddenControl(text: string): boolean {
  return /[\x00-\x08\x0b-\x1f\x7f-\x9f]/.test(text)
}

// A backtick fence the art cannot close early: at least three, and longer
// than any backtick run inside it.
export function fenceFor(art: string): string {
  let longest = 0
  for (const run of art.match(/`+/g) ?? []) longest = Math.max(longest, run.length)
  return '`'.repeat(Math.max(3, longest + 1))
}

// FNV-1a, 32 bits, over UTF-8 bytes, as 8 hex digits: names a state member.
export function fnv1a32(text: string): string {
  let h = 0x811c9dc5
  const eat = (b: number) => { h = Math.imul(h ^ b, 0x01000193) >>> 0 }
  for (const ch of text) {
    const cp = ch.codePointAt(0)!
    if (cp < 0x80) eat(cp)
    else if (cp < 0x800) { eat(0xc0 | (cp >> 6)); eat(0x80 | (cp & 63)) }
    else if (cp < 0x10000) { eat(0xe0 | (cp >> 12)); eat(0x80 | ((cp >> 6) & 63)); eat(0x80 | (cp & 63)) }
    else { eat(0xf0 | (cp >> 18)); eat(0x80 | ((cp >> 12) & 63)); eat(0x80 | ((cp >> 6) & 63)); eat(0x80 | (cp & 63)) }
  }
  return h.toString(16).padStart(8, '0')
}
