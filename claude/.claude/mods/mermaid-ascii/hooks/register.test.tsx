import { expect, mock, test } from 'claude-code/testing'
import type { On, ProcessRunResult } from 'claude-code'
import type { TestBody } from 'claude-code/testing'

// Nothing sits beneath the plugin: these hooks stand for the engine.

const SRC = 'flowchart LR\n  A --> B'
const OTHER = 'sequenceDiagram\n  A->>B: hi'
// A real FNV-1a 32 collision: both sources hash to d19e776c. The kit loads
// the mod in a module of its own, so a test cannot swap the hash function.
const COLLIDE_A = 'flowchart LR\n  A --> N108209'
const COLLIDE_B = 'flowchart LR\n  A --> N1087602'
const ART = '┌───┐\n│ A │\n└───┘'

const fence = (source: string) => '```mermaid\n' + source + '\n```'
const reply = (...parts: string[]) => parts.join('\n')
const asArt = (art: string, ticks = '```') => `${ticks}text\n${art}\n${ticks}`

const exited = (exitCode: number, stdout = ''): ProcessRunResult => ({
  exitCode,
  stdout,
  stderr: '',
  isStdoutTruncated: false,
  isStderrTruncated: false,
})

// `{ deny }` makes the plugin's `$.process.run` reject with that reason.
type Denied = { deny: string }
type Answer = (source: string) => ProcessRunResult | Denied | Promise<ProcessRunResult>

// The engine beneath: draws the text it is handed, answers the converter
// with `answer`, records toasts. Returns what the test reads back.
function engine(on: On, answer: Answer) {
  const runs: string[] = []
  const toasts: string[] = []
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>{(e.props as { text: string }).text}</Text>
  })
  on('fs.stat', () => ({
    value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: '/repo/render' },
  }))
  on('process.run', async (_, e) => {
    const source = e.init?.stdin ?? ''
    runs.push(source)
    const answered = await answer(source)
    return 'deny' in answered ? answered : { value: answered }
  })
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  return { runs, toasts }
}

function deferred<T>() {
  let resolve!: (v: T) => void
  let reject!: (err: unknown) => void
  const promise = new Promise<T>((res, rej) => { resolve = res; reject = rej })
  return { promise, resolve, reject }
}

const mountReply = (
  $: Parameters<TestBody>[0],
  surface: 'terminal' | 'desktop',
  text: string,
  columns = 80,
) =>
  $.ui.mount({
    plugin: 'mermaid-ascii',
    surface,
    component: 'AssistantMessage',
    props: { text, isFirstOfReply: true },
    viewport: { columns, rows: 24 },
  })

const shown = async (ui: { find: (q: { type: 'Text' }) => Promise<{ text?: string } | undefined> }) =>
  (await ui.find({ type: 'Text' }))?.text

test('a mermaid fence is drawn as source, then as art, on the terminal only', async ($, on) => {
  const clock = mock.clock(on)
  const { runs } = engine(on, () => exited(0, ART + '\n'))
  const text = reply('Here:', fence(SRC), 'Done.')

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await mountReply($, surface, text)
    if (surface === 'terminal') expect(await shown(ui)).toBe(text)
    await clock.settle()
    expect(await shown(ui)).toBe(
      surface === 'terminal' ? reply('Here:', asArt(ART), 'Done.') : text,
    )
    await ui.unmount()
  }
  expect(runs).toEqual([SRC])
})

test('a CRLF reply is converted, keeping its line endings', async ($, on) => {
  const clock = mock.clock(on)
  const { runs } = engine(on, () => exited(0, ART))
  const crlf = (s: string) => s.replaceAll('\n', '\r\n')
  const text = crlf(reply('Here:', fence(SRC), 'Done.'))

  const ui = await mountReply($, 'terminal', text)
  await clock.settle()
  expect(await shown(ui)).toBe(crlf(reply('Here:', asArt(ART), 'Done.')))
  // The converter gets the source as written, less the CRs.
  expect(runs).toEqual([SRC])
  await ui.unmount()
})

test('the output fence outlasts any backtick run in the art', async ($, on) => {
  const clock = mock.clock(on)
  const arts: Record<string, string> = {
    [SRC]: 'no ticks',
    [OTHER]: 'one ` tick',
    'stateDiagram-v2\n  [*] --> A': 'four ```` ticks',
  }
  engine(on, source => exited(0, arts[source]))
  const expected = [asArt('no ticks'), asArt('one ` tick'), asArt('four ```` ticks', '`````')]

  for (const [i, source] of Object.keys(arts).entries()) {
    const ui = await mountReply($, 'terminal', fence(source))
    await clock.settle()
    expect(await shown(ui)).toBe(expected[i])
    await ui.unmount()
  }
})

test('a failed conversion keeps the fence, is cached, and does not toast', async ($, on) => {
  const clock = mock.clock(on)
  const { runs, toasts } = engine(on, () => exited(1))
  const text = fence(SRC)

  const ui = await mountReply($, 'terminal', text)
  await clock.settle()
  expect(await shown(ui)).toBe(text)
  await ui.redraw()
  await clock.settle()
  expect(await shown(ui)).toBe(text)
  expect(runs).toHaveLength(1)
  expect(toasts).toEqual([])
  await ui.unmount()
})

test('art holding a control character keeps its fence, and the others still draw', async ($, on) => {
  const clock = mock.clock(on)
  // The engine skips a hook whose rewrite holds a control character, which
  // would leave every block of the reply as source: the good block drawing
  // as art is what shows the mod refused the bad art itself.
  const { runs, toasts } = engine(on, source =>
    exited(0, source === SRC ? '┌───┐\n│ \x1b[31mA │\n└───┘' : ART))
  const text = reply(fence(SRC), fence(OTHER))

  const ui = await mountReply($, 'terminal', text)
  await clock.settle()
  await ui.redraw()
  await clock.settle()
  expect(await shown(ui)).toBe(reply(fence(SRC), asArt(ART)))
  expect(runs).toHaveLength(2)
  expect(toasts).toEqual([])
  await ui.unmount()
})

test('a missing package (exit 3) toasts once however many blocks fail', async ($, on) => {
  const clock = mock.clock(on)
  const { runs, toasts } = engine(on, () => exited(3))
  const text = reply(fence(SRC), fence(OTHER))

  const ui = await mountReply($, 'terminal', text)
  await clock.settle()
  expect(await shown(ui)).toBe(text)
  expect(runs).toHaveLength(2)
  expect(toasts).toHaveLength(1)
  expect(toasts[0]).toContain('npm ci')
  await ui.unmount()
})

test('node that cannot start (ENOENT) toasts once', async ($, on) => {
  const clock = mock.clock(on)
  const { toasts } = engine(on, () => ({ deny: 'spawn node ENOENT' }))
  const text = reply(fence(SRC), fence(OTHER))

  const ui = await mountReply($, 'terminal', text)
  await clock.settle()
  expect(await shown(ui)).toBe(text)
  expect(toasts).toHaveLength(1)
  await ui.unmount()
})

test('a timeout keeps the fence and does not toast', async ($, on) => {
  const clock = mock.clock(on)
  const { runs, toasts } = engine(on, () => ({ deny: 'process.run: still running after 5000 ms' }))
  const text = fence(SRC)

  const ui = await mountReply($, 'terminal', text)
  await clock.settle()
  await ui.redraw()
  await clock.settle()
  expect(await shown(ui)).toBe(text)
  expect(runs).toHaveLength(1)
  expect(toasts).toEqual([])
  await ui.unmount()
})

test('a hash collision: the first source owns the id, the second stays source', async ($, on) => {
  const clock = mock.clock(on)
  const held = deferred<ProcessRunResult>()
  const { runs } = engine(on, () => held.promise)

  const a = await mountReply($, 'terminal', fence(COLLIDE_A))
  const b = await mountReply($, 'terminal', fence(COLLIDE_B))
  await clock.settle()
  // B found the id claimed by A, so only A's conversion started.
  expect(runs).toEqual([COLLIDE_A])

  held.resolve(exited(0, ART))
  await clock.settle()
  await b.redraw()
  expect(await shown(a)).toBe(asArt(ART))
  expect(await shown(b)).toBe(fence(COLLIDE_B))
  expect(runs).toEqual([COLLIDE_A])
  await a.unmount()
  await b.unmount()
})

test('a collision across a reload: the first result written keeps the id', async ($, on) => {
  // The store is the test's own, so it can play the other source's
  // conversion from before a reload landing while this one is in flight.
  const store = new Map<string, { value: unknown; version: number }>()
  const key = (e: { key: string; id?: string }) => `${e.key}/${e.id ?? ''}`
  on('state.get', (_, e) => ({ value: store.get(key(e)) ?? { value: undefined, version: 0 } }))
  on('state.set', (_, e) => {
    const now = store.get(key(e))?.version ?? 0
    if (e.ifVersion !== undefined && e.ifVersion !== now) {
      return { value: { isSet: false, version: now } }
    }
    store.set(key(e), { value: e.value, version: now + 1 })
    return { value: { isSet: true, version: now + 1 } }
  })
  const clock = mock.clock(on)
  const held = deferred<ProcessRunResult>()
  const { runs } = engine(on, () => held.promise)
  const member = 'art/d19e776c'

  // A then B: A's result lands first, B's conversion finishes after.
  const b = await mountReply($, 'terminal', fence(COLLIDE_B))
  await clock.settle()
  expect(runs).toEqual([COLLIDE_B])
  store.set(member, { value: { source: COLLIDE_A, ok: true, art: 'ART-A' }, version: 1 })
  held.resolve(exited(0, 'ART-B'))
  await clock.settle()
  expect(store.get(member)?.value).toEqual({ source: COLLIDE_A, ok: true, art: 'ART-A' })
  await b.redraw()
  expect(await shown(b)).toBe(fence(COLLIDE_B))
  await b.unmount()

  // B then A: B's result stands, and A finds it and stays source.
  store.set(member, { value: { source: COLLIDE_B, ok: true, art: 'ART-B' }, version: 2 })
  const a = await mountReply($, 'terminal', fence(COLLIDE_A))
  await clock.settle()
  expect(await shown(a)).toBe(fence(COLLIDE_A))
  expect(store.get(member)?.value).toEqual({ source: COLLIDE_B, ok: true, art: 'ART-B' })
  expect(runs).toEqual([COLLIDE_B])
  await a.unmount()
})

test('the same source in two replies starts one conversion', async ($, on) => {
  const clock = mock.clock(on)
  const held = deferred<ProcessRunResult>()
  const { runs } = engine(on, () => held.promise)

  const one = await mountReply($, 'terminal', reply('First', fence(SRC)))
  const two = await mountReply($, 'terminal', reply('Second', fence(SRC)))
  await clock.settle()
  held.resolve(exited(0, ART))
  await clock.settle()
  expect(runs).toEqual([SRC])
  expect(await shown(one)).toBe(reply('First', asArt(ART)))
  expect(await shown(two)).toBe(reply('Second', asArt(ART)))
  await one.unmount()
  await two.unmount()
})

test('a mermaid fence quoted inside a longer fence stays literal', async ($, on) => {
  const clock = mock.clock(on)
  const { runs } = engine(on, () => exited(0, ART))
  const text = reply('````markdown', fence(SRC), '````')

  const ui = await mountReply($, 'terminal', text)
  await clock.settle()
  expect(await shown(ui)).toBe(text)
  expect(runs).toEqual([])
  await ui.unmount()
})

test('art wider than the transcript keeps the fence, counted in display columns', async ($, on) => {
  const clock = mock.clock(on)
  // 10 CJK characters: 10 code points, 20 columns.
  const wide = '日本語日本語日本語日'
  engine(on, () => exited(0, wide))
  const text = fence(SRC)

  // 20 columns of art plus the 2-column reply indent: fits in 22, not in 21.
  const fits = await mountReply($, 'terminal', text, 22)
  await clock.settle()
  expect(await shown(fits)).toBe(asArt(wide))
  await fits.unmount()

  const narrow = await mountReply($, 'terminal', text, 21)
  expect(await shown(narrow)).toBe(text)
  await narrow.unmount()
})

test('marks and emoji: art fits at its display width and falls back one column short', async ($, on) => {
  const clock = mock.clock(on)
  // Each art line and its width in display columns.
  const cases: [string, number][] = [
    ['اٰ'.repeat(5), 5], // Arabic letter + combining mark
    ['אֿ'.repeat(5), 5], // Hebrew letter + combining mark
    ['❤️'.repeat(5), 10], // heart + VS16
    ['a‍b'.repeat(3), 6], // ZWJ between letters joins nothing
    ['\u{1f468}‍\u{1f469}‍\u{1f467}', 2], // emoji ZWJ sequence
  ]
  const art: Record<string, string> = {}
  cases.forEach(([line], i) => { art[`flowchart LR\n  N${i}`] = line })
  engine(on, source => exited(0, art[source]))

  for (const [i, [line, width]] of cases.entries()) {
    const text = fence(`flowchart LR\n  N${i}`)
    // The reply indent takes 2 columns.
    const fits = await mountReply($, 'terminal', text, width + 2)
    await clock.settle()
    expect([i, await shown(fits)]).toEqual([i, asArt(line)])
    await fits.unmount()

    const short = await mountReply($, 'terminal', text, width + 1)
    expect([i, await shown(short)]).toEqual([i, text])
    await short.unmount()
  }
})

test('an unclosed fence and a reply with no fence are unchanged', async ($, on) => {
  const clock = mock.clock(on)
  const { runs } = engine(on, () => exited(0, ART))

  for (const text of ['```mermaid\nflowchart LR\n  A --> B', 'Just prose.']) {
    const ui = await mountReply($, 'terminal', text)
    await clock.settle()
    expect(await shown(ui)).toBe(text)
    await ui.unmount()
  }
  expect(runs).toEqual([])
})
