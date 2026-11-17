import { expect, mock, test } from 'claude-code/testing'
import type { ModelCompleteInput, ModelCompleteResult, On, PromptOrigin, TurnStepResult } from 'claude-code'
import type { TestBody } from 'claude-code/testing'

// Nothing sits beneath the plugin: these hooks stand for the engine.

type $T = Parameters<TestBody>[0]
type Surface = 'terminal' | 'desktop'

const USAGE = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
// A real FNV-1a 32 collision (mermaid-ascii's): both hash to d19e776c.
const COLLIDE_A = 'flowchart LR\n  A --> N108209'
const COLLIDE_B = 'flowchart LR\n  A --> N1087602'
const STEP = { turnId: 't', index: 0, model: 'opus', messageCount: 1 }
const STEP_DONE: TurnStepResult = { turnId: 't', index: 0, answer: '', toolUses: [], stopReason: 'end_turn', usage: null }

const ko = (prompt: string) => `한국어 ${prompt}`
const answered = (text: string): ModelCompleteResult => ({ isAnswered: true, text, usage: USAGE })

function deferred<T>() {
  let resolve!: (v: T) => void
  const promise = new Promise<T>(res => { resolve = res })
  return { promise, resolve }
}

type Key = 'isOn' | 'seq' | 'lastPromptSeq' | 'fromSeq'
// What the mod's state holds before any write: its atoms' initial values.
const INITIAL: Record<Key, unknown> = { isOn: false, seq: 0, lastPromptSeq: 0, fromSeq: null }
// The test's `$` has no `state` noun, so writes are read as they pass
// beneath the plugin.

// The engine beneath: draws `engine:<text>` for any row, answers the model
// with `cfg.reply` (Korean by default), records every model call and every
// committed write of a plain key.
function engine(on: On) {
  const clock = mock.clock(on)
  const calls: ModelCompleteInput[] = []
  const registered: unknown[] = []
  const cfg = { reply: (e: ModelCompleteInput): ModelCompleteResult => answered(ko(e.prompt)) }
  const step = { gate: Promise.resolve() }
  const written: Record<string, unknown> = {}

  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => {
    registered.push(e)
    return { value: { command: 'kr' } }
  })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>{`engine:${(e.props as { text?: string }).text ?? ''}`}</Text>
  })
  on('model.complete', (_, e) => {
    calls.push(e)
    return { value: cfg.reply(e) }
  })
  on('turn.step', async function* () {
    await step.gate
    return STEP_DONE
  })
  on('state.set', async (_, e, next) => {
    const result = await next(e)
    const write = e as { plugin: string; key: string; id?: string; value: unknown }
    if (write.plugin === 'kr' && write.id === undefined) written[write.key] = write.value
    return result
  })
  return { clock, calls, registered, cfg, step, written }
}

const start = ($: $T) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
const kr = async ($: $T, args = '') =>
  (
    (await $.command.run({
      command: 'kr',
      args,
      origin: { kind: 'composer' },
      presentation: { isFullscreen: false, columns: 120 },
    })) as { text: string }
  ).text
const get = (t: { written: Record<string, unknown> }, key: Key) => (key in t.written ? t.written[key] : INITIAL[key])

const reply = ($: $T, requestId: string, text: string, surface: Surface = 'terminal', columns: number | null = 120) =>
  $.ui.mount({
    plugin: 'kr',
    surface,
    component: 'AssistantMessage',
    requestId,
    props: { text, isFirstOfReply: true },
    ...(columns === null ? {} : { viewport: { columns, rows: 40 } }),
  })

const prompt = ($: $T, requestId: string, text: string, origin: PromptOrigin = { kind: 'composer' }, surface: Surface = 'terminal') =>
  $.ui.mount({
    plugin: 'kr',
    surface,
    component: 'UserMessage',
    requestId,
    props: { text, origin, isExpanded: false },
  })

type Drawing = Awaited<ReturnType<typeof reply>>

// `EN` when the engine drew the row, else `<english> | <korean side>`.
async function view(ui: Drawing): Promise<string> {
  const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
  if (texts.some(t => t.startsWith('engine:'))) return 'EN'
  const md = (await ui.findAll({ type: 'Markdown' })).map(m => m.text)
  return `${md[0]} | ${md[1] ?? texts.find(t => t.startsWith('번역')) ?? '?'}`
}

// A conversation drawn and settled: prompt p1, reply r1, prompt p2, reply r2.
async function talk($: $T, clock: ReturnType<typeof mock.clock>, first = 'First.', second = 'Second.') {
  await prompt($, 'p1', 'one')
  const r1 = await reply($, 'r1', first)
  await prompt($, 'p2', 'two')
  const r2 = await reply($, 'r2', second)
  await clock.settle()
  return { r1, r2 }
}

test('/kr flips the mode, on and off set it, anything else answers the usage line', async ($, on) => {
  const t = engine(on)
  await start($)
  expect(t.registered).toEqual([
    { name: 'kr', description: 'Show replies in Korean beside English (this session)', argumentHint: '[on|off]' },
  ])
  expect(get(t, 'isOn')).toBe(false)
  expect(await kr($)).toBe('kr: on')
  expect(get(t, 'isOn')).toBe(true)
  expect(await kr($)).toBe('kr: off')
  expect(get(t, 'isOn')).toBe(false)
  expect(await kr($, ' on ')).toBe('kr: on')
  expect(await kr($, 'on')).toBe('kr: on')
  expect(get(t, 'isOn')).toBe(true)
  expect(await kr($, 'foo')).toBe('Usage: /kr [on|off]')
  expect(get(t, 'isOn')).toBe(true)
  expect(await kr($, 'off')).toBe('kr: off')
  expect(get(t, 'fromSeq')).toBe(null)
})

test('a first draw is English, takes one number, and a redraw takes none', async ($, on) => {
  const t = engine(on)
  await start($)
  expect(await kr($, 'on')).toBe('kr: on')
  const ui = await reply($, 'r1', 'Hello.')
  expect(await view(ui)).toBe('EN')
  // A redraw before the scheduled note runs claims nothing more.
  await ui.redraw()
  expect(get(t, 'seq')).toBe(0)
  await t.clock.settle()
  expect(get(t, 'seq')).toBe(1)
  expect(await view(ui)).toBe(`Hello. | ${ko('Hello.')}`)
  await ui.redraw()
  await t.clock.settle()
  expect(get(t, 'seq')).toBe(1)
})

test('a composer prompt moves the prompt boundary; a task notification and /kr do not', async ($, on) => {
  const t = engine(on)
  await start($)
  await prompt($, 'p1', 'one')
  await t.clock.settle()
  expect(get(t, 'lastPromptSeq')).toBe(1)
  await prompt($, 'n1', 'task done', { kind: 'task-notification' })
  await prompt($, 'k1', '/kr on')
  await t.clock.settle()
  expect(get(t, 'seq')).toBe(3)
  expect(get(t, 'lastPromptSeq')).toBe(1)
  await prompt($, 'p2', 'two', { kind: 'composer' }, 'desktop')
  await t.clock.settle()
  expect(get(t, 'lastPromptSeq')).toBe(4)
})

test('only the latest reply turns bilingual, even when an earlier one says the same', async ($, on) => {
  const t = engine(on)
  await start($)
  const { r1, r2 } = await talk($, t.clock, 'Done.', 'Done.')
  expect(await view(r2)).toBe('EN')
  expect(await kr($, 'on')).toBe('kr: on')
  await t.clock.settle()
  expect(await view(r1)).toBe('EN')
  expect(await view(r2)).toBe(`Done. | ${ko('Done.')}`)
  expect(t.calls.length).toBe(1)
})

test('with no prompt yet, a reply drawn after /kr on is eligible', async ($, on) => {
  const t = engine(on)
  await start($)
  expect(await kr($, 'on')).toBe('kr: on')
  expect(get(t, 'fromSeq')).toBe(0)
  const ui = await reply($, 'r1', 'Later.')
  await t.clock.settle()
  expect(await view(ui)).toBe(`Later. | ${ko('Later.')}`)
})

test('a reply drawn after /kr on, past a new prompt, is eligible', async ($, on) => {
  const t = engine(on)
  await start($)
  await talk($, t.clock)
  expect(await kr($, 'on')).toBe('kr: on')
  await prompt($, 'p3', 'three')
  const ui = await reply($, 'r3', 'Third.')
  await t.clock.settle()
  expect(await view(ui)).toBe(`Third. | ${ko('Third.')}`)
})

test('/kr on while on keeps what is eligible', async ($, on) => {
  const t = engine(on)
  await start($)
  const { r2 } = await talk($, t.clock)
  expect(await kr($, 'on')).toBe('kr: on')
  await prompt($, 'p3', 'three')
  await t.clock.settle()
  expect(await kr($, 'on')).toBe('kr: on')
  await t.clock.settle()
  expect(await view(r2)).toBe(`Second. | ${ko('Second.')}`)
})

test('while a model request streams, a reply waits; once it ends, one call', async ($, on) => {
  const t = engine(on)
  await start($)
  const gate = deferred<void>()
  t.step.gate = gate.promise
  const stream = $.turn.step(STEP)
  const first = stream.next()
  await prompt($, 'p1', 'one')
  const ui = await reply($, 'r1', 'Streaming.')
  await t.clock.settle()
  expect(await kr($, 'on')).toBe('kr: on')
  await t.clock.settle()
  expect(await view(ui)).toBe('Streaming. | 번역 중…')
  expect(t.calls.length).toBe(0)
  gate.resolve()
  expect(await first).toEqual({ done: true, value: STEP_DONE })
  await t.clock.settle()
  expect(t.calls.length).toBe(1)
  expect(await view(ui)).toBe(`Streaming. | ${ko('Streaming.')}`)
})

test('a subagent step does not hold translation back', async ($, on) => {
  const t = engine(on)
  await start($)
  const gate = deferred<void>()
  t.step.gate = gate.promise
  const stream = $.turn.step({ ...STEP, agentId: 'a1' })
  const first = stream.next()
  expect(await kr($, 'on')).toBe('kr: on')
  const ui = await reply($, 'r1', 'Main.')
  await t.clock.settle()
  expect(await view(ui)).toBe(`Main. | ${ko('Main.')}`)
  gate.resolve()
  await first
})

test('one call per distinct text, across redraws and repeated text', async ($, on) => {
  const t = engine(on)
  await start($)
  expect(await kr($, 'on')).toBe('kr: on')
  const a = await reply($, 'r1', 'Same.')
  const b = await reply($, 'r2', 'Same.')
  const c = await reply($, 'r3', 'Other.')
  await t.clock.settle()
  for (const ui of [a, b, c]) await ui.redraw()
  await t.clock.settle()
  expect(await view(b)).toBe(`Same. | ${ko('Same.')}`)
  expect(t.calls.map(c => c.prompt)).toEqual(['Same.', 'Other.'])
})

test('a failed translation draws its reason and is not retried', async ($, on) => {
  const t = engine(on)
  t.cfg.reply = () => ({ isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded', usage: USAGE })
  await start($)
  expect(await kr($, 'on')).toBe('kr: on')
  const ui = await reply($, 'r1', 'Busy.')
  await t.clock.settle()
  expect(await view(ui)).toBe('Busy. | 번역 실패 (api-error 529)')
  await ui.redraw()
  await t.clock.settle()
  expect(t.calls.length).toBe(1)
})

test('a reply that changes a code block draws code-changed', async ($, on) => {
  const t = engine(on)
  t.cfg.reply = () => answered('한국어, 코드 없음')
  await start($)
  expect(await kr($, 'on')).toBe('kr: on')
  const ui = await reply($, 'r1', 'Run `ls`.')
  await t.clock.settle()
  expect(await view(ui)).toBe('Run `ls`. | 번역 실패 (code-changed)')
})

test('off clears eligibility; on again reuses the cache with no new call', async ($, on) => {
  const t = engine(on)
  await start($)
  const { r2 } = await talk($, t.clock)
  expect(await kr($, 'on')).toBe('kr: on')
  await t.clock.settle()
  expect(await view(r2)).toBe(`Second. | ${ko('Second.')}`)
  expect(await kr($, 'off')).toBe('kr: off')
  await t.clock.settle()
  expect(await view(r2)).toBe('EN')
  expect(await kr($, 'on')).toBe('kr: on')
  await t.clock.settle()
  expect(await view(r2)).toBe(`Second. | ${ko('Second.')}`)
  expect(t.calls.length).toBe(1)

  // Off then on past a new prompt: the old reply is no longer the latest.
  expect(await kr($, 'off')).toBe('kr: off')
  await prompt($, 'p3', 'three')
  await t.clock.settle()
  expect(await kr($, 'on')).toBe('kr: on')
  await t.clock.settle()
  expect(await view(r2)).toBe('EN')
})

test('a hash collision draws English alone for the second text', async ($, on) => {
  const t = engine(on)
  await start($)
  expect(await kr($, 'on')).toBe('kr: on')
  const a = await reply($, 'r1', COLLIDE_A)
  const b = await reply($, 'r2', COLLIDE_B)
  await t.clock.settle()
  expect(await view(a)).toBe(`${COLLIDE_A} | ${ko(COLLIDE_A)}`)
  expect(await view(b)).toBe('EN')
  await b.redraw()
  await t.clock.settle()
  expect(await view(b)).toBe('EN')
  expect(t.calls.length).toBe(1)
})

test('after a reload, a cached translation of a colliding text draws English', async ($, on) => {
  const t = engine(on)
  // What an earlier load stored for COLLIDE_A; this load's claims are empty.
  on('state.get', (_, e, next) => {
    const read = e as { plugin: string; key: string; id?: string }
    if (read.plugin === 'kr' && read.key === 'ko' && read.id === 'd19e776c') {
      return { value: { value: { source: COLLIDE_A, ok: true, text: ko(COLLIDE_A) }, version: 1 } }
    }
    return next(e)
  })
  await start($)
  expect(await kr($, 'on')).toBe('kr: on')
  const a = await reply($, 'r1', COLLIDE_A)
  const b = await reply($, 'r2', COLLIDE_B)
  await t.clock.settle()
  expect(await view(a)).toBe(`${COLLIDE_A} | ${ko(COLLIDE_A)}`)
  expect(await view(b)).toBe('EN')
  expect(t.calls.length).toBe(0)
})

test('off, a reply is drawn by the engine and nothing is translated', async ($, on) => {
  const t = engine(on)
  await start($)
  const { r2 } = await talk($, t.clock)
  expect(await view(r2)).toBe('EN')
  expect(t.calls.length).toBe(0)
  // The same reply turns bilingual once on, so the hook did run above.
  expect(await kr($, 'on')).toBe('kr: on')
  await t.clock.settle()
  expect(await view(r2)).toBe(`Second. | ${ko('Second.')}`)
})

test('desktop passes through, while its draws still count', async ($, on) => {
  const t = engine(on)
  await start($)
  expect(await kr($, 'on')).toBe('kr: on')
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await reply($, `r-${surface}`, 'Both.', surface)
    await t.clock.settle()
    expect(await view(ui)).toBe(surface === 'terminal' ? `Both. | ${ko('Both.')}` : 'EN')
    await ui.unmount()
  }
  expect(get(t, 'seq')).toBe(2)
})

test('side by side from 105 columns, stacked below and with no viewport', async ($, on) => {
  const t = engine(on)
  await start($)
  expect(await kr($, 'on')).toBe('kr: on')
  const cases: [number | null, string][] = [[120, 'row'], [104, 'column'], [null, 'column']]
  for (const [i, [columns, direction]] of cases.entries()) {
    const ui = await reply($, `r${i}`, 'Wide.', 'terminal', columns)
    await t.clock.settle()
    expect(await view(ui)).toBe(`Wide. | ${ko('Wide.')}`)
    expect((await ui.find({ type: 'Box' }))?.props.flexDirection, `${columns}`).toBe(direction)
    await ui.unmount()
  }
})
