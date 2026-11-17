// The translation call (spec "Translation call"): protect code, ask haiku,
// check and restore. Everything but `translate` is pure.
import type { EngineInterface } from 'claude-code'

export type Result = { ok: true; text: string } | { ok: false; reason: string }

const SYSTEM = [
  'Translate the given Markdown from English to natural Korean.',
  'Copy every ⟦K<n>⟧ placeholder exactly, once each, in place.',
  'Keep every ⟦N<n>⟧ marker on its own line, in order, and translate the text under each.',
  'Keep file paths, commands, flags, identifiers and technical terms in English.',
  'Keep the Markdown structure.',
  'Output only the translation.',
].join('\n')

const MAX_TOKENS = 8192

// Fence rules as in mermaid-ascii R1: three or more backticks or tildes,
// closed by the same character at least as many times on a line of its own.
const OPEN = /^( {0,3})(`{3,}|~{3,})(.*)$/
const CLOSE = /^ {0,3}(`{3,}|~{3,})[ \t]*$/

// Line indexes of each closed top-level fence. A fence inside another is part
// of the outer one. A trailing CR is ignored when matching.
function scanFences(lines: string[]): { start: number; end: number }[] {
  const found: { start: number; end: number }[] = []
  let open: { run: string; start: number } | undefined
  lines.forEach((raw, i) => {
    const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw
    if (!open) {
      const m = OPEN.exec(line)
      if (!m) return
      const [, , run = '', info = ''] = m
      // A backtick fence's info string may not hold a backtick.
      if (!(run.startsWith('`') && info.includes('`'))) open = { run, start: i }
      return
    }
    const run = CLOSE.exec(line)?.[1]
    if (run && run[0] === open.run[0] && run.length >= open.run.length) {
      found.push({ start: open.start, end: i })
      open = undefined
    }
  })
  return found
}

// Inline code spans in one paragraph: a backtick run closed by the next run
// of exactly the same length. An unmatched run is text.
function inlineSpans(chunk: string): [number, number][] {
  const found: [number, number][] = []
  const runEnd = (k: number) => {
    while (chunk[k] === '`') k++
    return k
  }
  let i = 0
  while (i < chunk.length) {
    if (chunk[i] !== '`') { i++; continue }
    const j = runEnd(i)
    let k = j
    let close = -1
    while (k < chunk.length) {
      if (chunk[k] !== '`') { k++; continue }
      const m = runEnd(k)
      if (m - k === j - i) { close = m; break }
      k = m
    }
    if (close < 0) { i = j; continue }
    found.push([i, close])
    i = close
  }
  return found
}

// Replaces each top-level fenced block and each inline code span with
// ⟦K<n>⟧, numbered from 0 in order; `spans[n]` is the exact original.
export function protect(source: string): { text: string; spans: string[] } {
  const lines = source.split('\n')
  const fences = scanFences(lines)
  const spans: string[] = []
  const out: string[] = []
  const hold = (span: string) => `⟦K${spans.push(span) - 1}⟧`

  // A paragraph: consecutive lines that are neither blank nor fenced.
  let para: string[] = []
  const flush = () => {
    if (para.length === 0) return
    const chunk = para.join('\n')
    let text = ''
    let at = 0
    for (const [from, to] of inlineSpans(chunk)) {
      text += chunk.slice(at, from) + hold(chunk.slice(from, to))
      at = to
    }
    out.push(text + chunk.slice(at))
    para = []
  }

  let f = 0
  for (let i = 0; i < lines.length; i++) {
    const fence = fences[f]
    if (fence && i === fence.start) {
      flush()
      out.push(hold(lines.slice(fence.start, fence.end + 1).join('\n')))
      i = fence.end
      f++
      continue
    }
    const line = lines[i]!
    if (line.trim() === '') {
      flush()
      out.push(line)
    } else para.push(line)
  }
  flush()
  return { text: out.join('\n'), spans }
}

// Every placeholder must appear exactly once, and no other may appear.
export function restore(reply: string, spans: string[]): Result {
  const seen = reply.match(/⟦K\d+⟧/g) ?? []
  if (seen.length !== spans.length) return { ok: false, reason: 'code-changed' }
  for (let n = 0; n < spans.length; n++) {
    if (reply.split(`⟦K${n}⟧`).length !== 2) return { ok: false, reason: 'code-changed' }
  }
  return { ok: true, text: reply.replace(/⟦K(\d+)⟧/g, (_, n: string) => spans[Number(n)]!) }
}

// For a source sent unprotected: its code, in order, must be byte-equal in
// the reply.
export function codeEqual(source: string, reply: string): boolean {
  const a = protect(source).spans
  const b = protect(reply).spans
  return a.length === b.length && a.every((span, i) => span === b[i])
}

// AskUserQuestion fields in one source: each under its own ⟦N<n>⟧ line.
export function numbered(fields: string[]): string {
  return fields.map((field, i) => `⟦N${i + 1}⟧\n${field}`).join('\n\n')
}

export function split(reply: string, count: number): { ok: true; parts: string[] } | { ok: false; reason: string } {
  const failed = { ok: false, reason: 'count-mismatch' } as const
  const marks = [...reply.matchAll(/^⟦N(\d+)⟧[ \t]*\r?$/gm)]
  if (marks.length !== count || marks.some((m, i) => Number(m[1]) !== i + 1)) return failed
  if (count > 0 && reply.slice(0, marks[0]!.index).trim() !== '') return failed
  const parts = marks.map((m, i) => {
    const from = m.index + m[0].length
    const to = i + 1 < marks.length ? marks[i + 1]!.index : reply.length
    return reply.slice(from, to).trim()
  })
  return { ok: true, parts }
}

// Message text may hold no control character but tab and newline
// (mermaid-ascii R7): the engine skips a hook whose tree holds one.
function hasForbiddenControl(text: string): boolean {
  return /[\x00-\x08\x0b-\x1f\x7f-\x9f]/.test(text)
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

export async function translate($: EngineInterface, source: string, timeoutMs: number): Promise<Result> {
  // A source that already holds a placeholder's opening is sent as written.
  const held = source.includes('⟦K') ? null : protect(source)
  const r = await $.model.complete({
    model: 'haiku',
    system: [{ text: SYSTEM, cache: true }],
    prompt: held ? held.text : source,
    maxTokens: Math.min(MAX_TOKENS, 4 * Math.ceil(source.length / 3)),
    timeoutMs,
  })
  if (!r.isAnswered) {
    if (r.reason === 'api-error') return { ok: false, reason: r.status === null ? 'api-error' : `api-error ${r.status}` }
    return { ok: false, reason: r.reason }
  }
  if (hasForbiddenControl(r.text)) return { ok: false, reason: 'control-char' }
  if (held) return restore(r.text, held.spans)
  return codeEqual(source, r.text) ? { ok: true, text: r.text } : { ok: false, reason: 'code-changed' }
}
