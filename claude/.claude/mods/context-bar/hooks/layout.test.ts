import { expect, test } from 'claude-code/testing'

import type { SessionUsage } from 'claude-code'

import { EXAMPLE, row, usage } from './fixtures'
import { apportion, labelFor, layout, percent, reduce, shortTokens, spread } from './layout'
import type { Reading } from '../types'
import type { Span } from './layout'

// What every apportionment holds (spec R3): whole counts ≥ 0 summing to width.
function holds(counts: number[], width: number): void {
  expect(counts.every(c => Number.isInteger(c) && c >= 0), `counts ${counts}`).toBe(true)
  expect(counts.reduce((a, b) => a + b, 0), `sum of ${counts}`).toBe(width)
}

const cells = (tokens: number[], width: number, fill = tokens.length - 1) => {
  const counts = apportion(tokens, width, fill)
  holds(counts, width)
  return counts
}

test('shortTokens writes R5 short tokens', () => {
  const cases: [number, string][] = [
    [0, '0'],
    [950, '950'],
    [999, '999'],
    [1000, '1k'],
    [4200, '4.2k'],
    [9949, '9.9k'],
    [9950, '10k'],
    [17_000, '17k'],
    [897_000, '897k'],
    [999_000, '999k'],
    [999_500, '1M'],
    [1_000_000, '1M'],
    [1_020_000, '1.02M'],
    [1_500_000, '1.5M'],
    [9_990_000, '9.99M'],
  ]
  expect(cases.map(([n]) => shortTokens(n))).toEqual(cases.map(([, s]) => s))
})

test('shortTokens is at most 5 columns up to 9.99M (R7 inline prefix)', () => {
  for (let n = 0; n <= 9_990_000; n += n < 20_000 ? 7 : 997) {
    const s = shortTokens(n)
    if (s.length > 5) throw new Error(`${n} → ${s}`)
  }
})

test('percent is whole, and any non-zero share shows at least 1%', () => {
  expect([
    percent(0, 1_000_000),
    percent(1, 1_000_000),
    percent(4200, 1_000_000),
    percent(17_000, 1_000_000),
    percent(52_000, 1_000_000),
    percent(1_020_000, 1_000_000),
    percent(5, 0),
  ]).toEqual(['0%', '1%', '1%', '2%', '5%', '102%', '0%'])
})

test('labelFor maps /context names, by kind first', () => {
  const used = (name: string) => labelFor({ name, kind: 'used' })
  expect([
    used('System prompt'),
    used('System tools'),
    used('MCP tools'),
    used('Custom agents'),
    used('Memory files'),
    used('Skills'),
    used('Messages'),
    used('Slash Commands'),
    labelFor({ name: 'Free space', kind: 'free' }),
    labelFor({ name: 'Messages', kind: 'free' }),
    labelFor({ name: 'Autocompact buffer', kind: 'buffer' }),
    labelFor({ name: 'Free space', kind: 'buffer' }),
  ]).toEqual([
    'system prompt',
    'tools',
    'mcp tools',
    'agents',
    'memory files',
    'skills',
    'messages',
    'slash commands',
    'free',
    'free',
    'reserved',
    'reserved',
  ])
})

test('apportion: three equal parts over the window split it evenly', () => {
  // Over the window: free and reserved are 0 and the used parts share D.
  expect(cells([100, 100, 100, 0, 0], 60, 3)).toEqual([20, 20, 20, 0, 0])
})

test('apportion: each small part gets one cell, taken from the largest', () => {
  const tokens = [400_000, 300_000, 1000, 900, 800, 700, 600, 296_000]
  const counts = cells(tokens, 72)
  // Largest remainder alone: [29, 22, 0, 0, 0, 0, 0, 21].
  expect(counts).toEqual([24, 22, 1, 1, 1, 1, 1, 21])
})

test('apportion: more parts than cells, similar sizes: the 6 largest get one', () => {
  const tokens = [110, 190, 120, 180, 130, 170, 140, 160, 150]
  expect(cells(tokens, 6)).toEqual([0, 1, 0, 1, 0, 1, 1, 1, 1])
})

test('apportion: skewed and crowded keeps the second part visible', () => {
  // Largest remainder alone gives [2, 0, 0, 0].
  expect(cells([1000, 9, 8, 7], 2)).toEqual([1, 1, 0, 0])
})

test('apportion: a 0-token part gets 0 cells, a 1-token part gets 1', () => {
  expect(cells([0, 1, 1_000_000], 60)).toEqual([0, 1, 59])
})

test('apportion: remainder ties go to the earlier part', () => {
  // Each gets 1.5 cells: one extra cell, to the first.
  expect(cells([1, 1], 3)).toEqual([2, 1])
})

test('apportion: donor ties come from the later part', () => {
  // [5, 5, 0] by largest remainder; the 1-token part takes from the second.
  expect(cells([500, 500, 1], 10)).toEqual([5, 4, 1])
})

test('apportion: k > width ties go to the earlier part', () => {
  expect(cells([5, 5, 5], 2)).toEqual([1, 1, 0])
})

test('apportion: D = 0 gives the whole bar to the fill part', () => {
  expect(cells([0, 0, 0, 0], 40, 2)).toEqual([0, 0, 40, 0])
})

// mulberry32: a seeded generator, so a failing run repeats.
function rng(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

test('apportion: property check over 500 seeded runs', () => {
  const random = rng(20261023)
  const int = (lo: number, hi: number) => lo + Math.floor(random() * (hi - lo + 1))
  let skewed = 0
  let crowded = 0
  for (let run = 0; run < 500; run++) {
    const n = int(1, 12)
    const tokens = Array.from({ length: n }, () => (random() < 0.2 ? 0 : int(1, 1000)))
    if (random() < 0.3) {
      tokens[int(0, n - 1)] = int(1, 1000) * 1000
      skewed++
    }
    const width = int(1, 120)
    const fill = int(0, n - 1)
    const counts = apportion(tokens, width, fill)
    const where = `run ${run}: ${JSON.stringify({ tokens, width, fill, counts })}`
    holds(counts, width)

    const parts = tokens.map((t, i) => ({ i, t, cells: counts[i] ?? -1 }))
    const nonZero = parts.filter(p => p.t > 0)
    if (nonZero.length === 0) {
      expect(counts[fill], where).toBe(width)
    } else if (nonZero.length <= width) {
      for (const p of parts) {
        expect(p.t > 0 ? p.cells >= 1 : p.cells === 0, where).toBe(true)
      }
    } else {
      crowded++
      const chosen = [...nonZero].sort((a, b) => b.t - a.t || a.i - b.i).slice(0, width)
      expect(counts, where).toEqual(parts.map(p => (chosen.includes(p) ? 1 : 0)))
    }
  }
  // The run must reach both branches and the skewed shape.
  expect(skewed > 50 && crowded > 10, `skewed ${skewed}, crowded ${crowded}`).toBe(true)
})

// --- reduce and layout (step 3) ---

const text = (r: Span[]) => r.map(s => s.text).join('')
const texts = (rows: Span[][] | null | undefined) => (rows ?? []).map(text)
const band = (u: SessionUsage, width: number) => {
  const reading = reduce(u)
  if (reading === null) throw new Error('no reading')
  return layout(reading, width)
}
const at = (u: SessionUsage, width: number) => band(u, width)?.rows ?? null
const plain = (s: string): Span[] => [{ text: s }]

// A reading of `total` used tokens in a 1M window that compacts at 987k.
const reading = (total: number): Reading => ({
  used: [{ label: 'messages', tokens: total, color: 'merged' }],
  free: { label: 'free', tokens: Math.max(0, 987_000 - total), color: 'inactive' },
  reserved: { label: 'reserved', tokens: 13_000, color: 'inactive' },
  totalTokens: total,
  window: 1_000_000,
  compactsAt: 987_000,
})

test('reduce sorts rows by kind and drops deferred ones', () => {
  expect(reduce(usage())).toEqual({
    used: [
      { label: 'system prompt', tokens: 4200, color: 'promptBorder' },
      { label: 'tools', tokens: 17_000, color: 'inactive' },
      { label: 'mcp tools', tokens: 52_000, color: 'suggestion' },
      { label: 'agents', tokens: 3400, color: 'permission' },
      { label: 'memory files', tokens: 8600, color: 'claude' },
      { label: 'skills', tokens: 5100, color: 'warning' },
      { label: 'messages', tokens: 0, color: 'merged' },
    ],
    free: { label: 'free', tokens: 896_700, color: 'promptBorder' },
    reserved: { label: 'reserved', tokens: 13_000, color: 'inactive' },
    totalTokens: 90_300,
    window: 1_000_000,
    compactsAt: 987_000,
  })
})

test('reduce: a missing free row is 0 tokens, a missing buffer is null', () => {
  const r = reduce(usage({ categories: [row('Messages', 10)] }))
  expect([r?.free, r?.reserved]).toEqual([{ label: 'free', tokens: 0, color: 'inactive' }, null])
})

test('reduce: no breakdown, or no used row, is no reading', () => {
  expect(reduce(usage(null))).toBeNull()
  expect(reduce(usage({ categories: [row('Free space', 10, 'free')] }))).toBeNull()
})

test('reduce: compactsAt is null with auto-compact off or no threshold', () => {
  expect(reduce(usage({ isAutoCompactEnabled: false }))?.compactsAt).toBeNull()
  const u = usage()
  const b = u.context.breakdown
  if (!b) throw new Error('no breakdown')
  const noThreshold = { ...u, context: { ...u.context, breakdown: { ...b, autoCompactThreshold: undefined } } }
  expect(reduce(noThreshold)?.compactsAt).toBeNull()
})

test("layout draws the intent's example framed at width 76", () => {
  const b = band(usage(), 76)
  expect(b?.isFramed).toBe(true)
  expect(texts(b?.rows)).toEqual([
    '◆ context' + ' '.repeat(30) + '90k of 1M · compacts at 987k  9% ',
    '█'.repeat(9) + '░'.repeat(62) + '│',
    '■ system prompt 4.2k 1%  ■ tools 17k 2%  ■ mcp tools 52k 5%',
    '■ agents 3.4k 1%  ■ memory files 8.6k 1%  ■ skills 5.1k 1%',
    '■ messages 0 0%  ■ free 897k',
  ])
})

test('layout with auto-compact off has no compacts-at and no marker', () => {
  const categories = EXAMPLE.filter(c => c.kind !== 'buffer').map(c =>
    c.kind === 'free' ? { ...c, tokens: 909_700 } : c)
  const rows = texts(at(usage({ categories, isAutoCompactEnabled: false }), 76))
  expect(rows[0]).toBe('◆ context' + ' '.repeat(49) + '90k of 1M  9% ')
  expect(rows[1]).toBe('█'.repeat(9) + '░'.repeat(63))
  expect(rows.at(-1)).toBe('■ messages 0 0%  ■ free 910k')
})

test('layout over the window: the true total, and every cell used', () => {
  const categories = [
    row('System prompt', 20_000),
    row('Messages', 1_000_000, 'used', 'merged'),
    row('Free space', 5000, 'free'),
    row('Autocompact buffer', 13_000, 'buffer'),
  ]
  const rows = texts(at(usage({ categories }), 64))
  expect(rows[0]?.endsWith('1.02M of 1M · compacts at 987k  102% ')).toBe(true)
  expect(rows[1]).toBe('█'.repeat(60))
  expect(rows.slice(2).join('  ')).toBe('■ system prompt 20k 2%  ■ messages 1M 100%  ■ free 0')
})

test('layout follows the R7 tiers and never overflows', () => {
  const u = usage()
  expect([band(u, 80)?.isFramed, texts(at(u, 80)).length]).toEqual([true, 5])
  expect(band(u, 60)?.isFramed).toBe(true)
  expect(texts(at(u, 60))[0]).toContain('90k of 1M · compacts at 987k  9% ')
  for (const w of [59, 40]) {
    const rows = texts(at(u, w))
    expect([w, band(u, w)?.isFramed, rows.length, rows[0]?.endsWith(' 90k/1M  9% '), rows[1]?.length])
      .toEqual([w, false, 2, true, w])
  }
  for (const w of [39, 20]) {
    const rows = texts(at(u, w))
    expect([w, band(u, w)?.isFramed, rows.length, rows[0]?.startsWith('◆ 90k/1M █')])
      .toEqual([w, false, 1, true])
  }
  expect(band(u, 19)).toBeNull()

  const long = usage({ categories: [...EXAMPLE, row('x'.repeat(100), 10)] })
  for (const fixture of [u, long]) {
    for (let w = 19; w <= 120; w++) {
      const room = w >= 60 ? w - 4 : w
      for (const r of texts(at(fixture, w))) {
        if (r.length > room) throw new Error(`width ${w}: ${r.length} columns: ${r}`)
      }
      if (w >= 20) expect(texts(at(fixture, w))[w >= 40 ? 1 : 0]?.length).toBe(room)
    }
  }
})

test('layout at width 20 leaves the inline bar at least 6 cells', () => {
  const big = usage({ categories: [row('Messages', 9_990_000)], rawMaxTokens: 9_990_000 })
  const [inline] = texts(at(big, 20))
  expect(inline).toBe('◆ 9.99M/9.99M ' + '█'.repeat(6))
})

test('spread: when the header parts collide, context is cut, never the figures', () => {
  const right = plain('90k of 1M · compacts at 987k  9% ')
  expect(text(spread(plain('◆ context'), right, 44))).toBe('◆ context  90k of 1M · compacts at 987k  9% ')
  expect(text(spread(plain('◆ context'), right, 36))).toBe('◆… 90k of 1M · compacts at 987k  9% ')
  expect(text(spread(plain('◆ context'), right, 34))).toBe(' 90k of 1M · compacts at 987k  9% ')
})

test('legend entries are never split, and one wider than the room is cut', () => {
  const rows = texts(at(usage({ categories: [...EXAMPLE, row('x'.repeat(100), 10)] }), 60))
  const legend = rows.slice(2)
  // Every entry starts a row or follows two spaces: none is split.
  for (const r of legend) expect(r.startsWith('■ ')).toBe(true)
  expect(legend.join('  ').split('  ■ ').length).toBe(9)
  expect(legend).toContain('■ ' + 'x'.repeat(53) + '…')
})

test('an entry cut where one span ends still ends in …', () => {
  // '■ ' + 50 x + ' 10 ' is exactly the 56 columns inside the frame, so the
  // percent span is the first one left out: the cut must still show.
  const r: Reading = {
    used: [{ label: 'x'.repeat(50), tokens: 10, color: 'claude' }],
    free: { label: 'free', tokens: 999_990, color: 'inactive' },
    reserved: null,
    totalTokens: 10,
    window: 1_000_000,
    compactsAt: null,
  }
  expect(texts(layout(r, 60)?.rows)[2]).toBe('■ ' + 'x'.repeat(50) + ' 10…')
})

test('glyphs and colours: used █, free ░, the marker │ then the reserve dimmed', () => {
  const bar = at(usage(), 76)?.[1] ?? []
  expect(bar.map(s => [s.text[0], s.text.length, s.color, s.dim ?? false])).toEqual([
    ['█', 1, 'promptBorder', false],
    ['█', 1, 'inactive', false],
    ['█', 4, 'suggestion', false],
    ['█', 1, 'permission', false],
    ['█', 1, 'claude', false],
    ['█', 1, 'warning', false],
    ['░', 62, 'promptBorder', false],
    ['│', 1, 'warning', false],
  ])
  const wide = { ...reading(400_000), free: { label: 'free', tokens: 500_000, color: 'inactive' } }
  const tail = layout({ ...wide, reserved: { label: 'reserved', tokens: 100_000, color: 'inactive' } }, 64)
  expect((tail?.rows[1] ?? []).map(s => [s.text[0], s.text.length, s.color, s.dim ?? false])).toEqual([
    ['█', 24, 'merged', false],
    ['░', 30, 'inactive', false],
    ['│', 1, 'warning', false],
    ['░', 5, 'inactive', true],
  ])
})

test('emphasis: bold figures, dim context, the swatch coloured', () => {
  const rows = at(usage(), 76) ?? []
  const find = (r: number, s: string) => (rows[r] ?? []).find(span => span.text === s)
  expect(find(0, '◆')?.color).toBe('claude')
  expect(find(0, ' context')?.bold).toBe(true)
  expect(find(0, '90k')?.bold).toBe(true)
  expect(find(0, ' of 1M · compacts at 987k')?.dim).toBe(true)
  expect(find(2, '■')?.color).toBe('promptBorder')
  expect(find(2, '4.2k')?.bold).toBe(true)
  expect(find(2, '1%')?.dim).toBe(true)
  expect(find(4, ' free 897k')?.dim).toBe(true)
})

test('the badge is green below 70%, yellow from 70% and red from 90%', () => {
  const badge = (total: number) => {
    const header = layout(reading(total), 80)?.rows[0] ?? []
    const s = header.at(-1)
    return [s?.text, s?.color, s?.background]
  }
  expect([badge(690_000), badge(700_000), badge(900_000)]).toEqual([
    [' 69% ', 'inverseText', 'success'],
    [' 70% ', 'inverseText', 'warning'],
    [' 90% ', 'inverseText', 'error'],
  ])
})
