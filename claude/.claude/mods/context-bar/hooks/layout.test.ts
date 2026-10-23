import { expect, test } from 'claude-code/testing'

import { apportion, labelFor, percent, shortTokens } from './layout'

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
