import { expect, mock, test } from 'claude-code/testing'
import type { On, RenderPropsOf, SessionCompactResult, SessionMessage, SessionUsage } from 'claude-code'
import type { TestBody } from 'claude-code/testing'

import { row, usage } from './fixtures'

// Nothing sits beneath the plugin: these hooks stand for the engine.

type $T = Parameters<TestBody>[0]
type Answer = SessionUsage | { deny: string }
type BandProps = RenderPropsOf['AbovePrompt']

const PROPS: BandProps = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 10,
  bodyColumns: 80,
  scroll: { offset: 0, bodyRows: 10 },
  view: {},
}
const BAND = { plugin: 'context-bar', component: 'AbovePrompt', props: PROPS } as const
const TURN = { answer: '', durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' } as const
const MESSAGES: SessionMessage[] = [{ role: 'user', text: 'hi', toolUses: [] }]
const COMPACTED: SessionCompactResult = { messages: [{ role: 'assistant', text: 'summary', toolUses: [] }] }

// A reading whose header reads `<n>k of 1M`.
const reading = (n: number) => usage({ categories: [row('Messages', n * 1000)] })

function deferred<T>() {
  let resolve!: (v: T) => void
  const promise = new Promise<T>(res => { resolve = res })
  return { promise, resolve }
}

// The engine beneath the plugin. `answers` are handed out in order, one per
// usage() call, then `fallback`; `hold()` holds the next write of the
// reading until released; `commits` records each committed reading's total
// in thousands (null for a clear), in commit order.
function engine(on: On, stored: Record<string, unknown> = {}) {
  const clock = mock.clock(on)
  const store: Record<string, unknown> = { ...stored }
  const asked: unknown[] = []
  const logs: string[] = []
  const commits: (number | null)[] = []
  const answers: (Answer | Promise<Answer>)[] = []
  const cfg = { fallback: reading(1) as Answer, compact: COMPACTED as SessionCompactResult | Promise<SessionCompactResult> }
  let gate: Promise<void> | null = null

  on('command.register', () => ({ value: { command: 'context-bar' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('turn.complete', () => ({ text: 'done' }))
  on('session.compact', () => cfg.compact)
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  on('ui.log', (_, e) => {
    logs.push(e.text)
    return { value: undefined }
  })
  on('store.get', (_, e) => ({ value: store[e.key] }))
  on('store.set', (_, e) => {
    store[e.key] = e.value
    return { value: undefined }
  })
  on('session.usage', async (_, e) => {
    asked.push(e)
    const answer = await (answers.shift() ?? cfg.fallback)
    return 'deny' in answer ? answer : { value: answer }
  })
  on('state.set', async (_, e, next) => {
    const write = e as { key: string; value: { value: { totalTokens: number } | null } }
    if (write.key !== 'reading') return next(e)
    const held = gate
    gate = null
    if (held) await held
    const result = await next(e)
    commits.push(write.value.value === null ? null : write.value.value.totalTokens / 1000)
    return result
  })

  return {
    clock,
    store,
    asked,
    logs,
    commits,
    answers,
    cfg,
    // Holds the next write of the reading; returns its release.
    hold(): () => void {
      const d = deferred<void>()
      gate = d.promise
      return () => d.resolve()
    },
  }
}

const start = ($: $T) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
const turn = ($: $T, agentId?: string) => $.turn.complete(agentId ? { ...TURN, agentId } : TURN)
const compact = ($: $T, trigger: 'manual' | 'precompute' = 'manual', agentId?: string) =>
  $.session.compact({ trigger, messages: [...MESSAGES], ...(agentId ? { agentId } : {}) })
const command = ($: $T, args = '') =>
  $.command.run({
    command: 'context-bar',
    args,
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  })

// What the band shows, read on terminal and desktop alike: 'engine' when it
// stepped aside, else the header's used figure ('10k').
async function seen($: $T, props: Partial<BandProps> = {}): Promise<string> {
  const views: string[] = []
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, props: { ...BAND.props, ...props }, surface })
    const text = (await ui.find({ type: 'Text' }))?.text ?? ''
    views.push(text === 'engine' ? 'engine' : (/ ([\d.]+[kM]?) of /.exec(text)?.[1] ?? `?${text}`))
    await ui.unmount()
  }
  expect(views[0], 'terminal and desktop differ').toBe(views[1])
  return views[0] ?? ''
}

test('off by default: the band passes through and usage() is never called', async ($, on) => {
  const t = engine(on)
  await start($)
  await turn($)
  await compact($)
  await t.clock.settle()
  expect(await seen($)).toBe('engine')
  expect(t.asked).toEqual([])
  // The same band draws once turned on, so the hidden band above was real.
  expect(await command($)).toEqual({ text: 'Context bar on.' })
  await t.clock.settle()
  expect(await seen($)).toBe('1k')
})

test('/context-bar turns it on and keeps that for the next session', async ($, on) => {
  const t = engine(on)
  await start($)
  expect(await command($)).toEqual({ text: 'Context bar on.' })
  await t.clock.settle()
  expect(t.store.isOn).toBe(true)
  expect(t.asked).toEqual([{ breakdown: 'summary' }])
  expect(await seen($)).toBe('1k')
})

test("a session's start reads the stored setting and draws at once", async ($, on) => {
  const t = engine(on, { isOn: true })
  t.cfg.fallback = reading(7)
  await start($)
  await t.clock.settle()
  expect(await seen($)).toBe('7k')
})

test('/context-bar off clears the reading; a bad argument changes nothing', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  expect(await seen($)).toBe('1k')
  expect(await command($, 'bogus')).toEqual({ text: 'Usage: /context-bar [on|off]' })
  await t.clock.settle()
  expect([await seen($), t.store.isOn, t.asked.length]).toEqual(['1k', true, 1])
  expect(await command($, 'off')).toEqual({ text: 'Context bar off.' })
  await t.clock.settle()
  expect([await seen($), t.store.isOn, t.commits.at(-1)]).toEqual(['engine', false, null])
  expect(await command($)).toEqual({ text: 'Context bar on.' })
  expect(await command($, ' on ')).toEqual({ text: 'Context bar on.' })
})

test('a main-loop turn refreshes; a subagent turn does not', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  t.cfg.fallback = reading(20)
  await turn($, 'agent-1')
  await t.clock.settle()
  expect([await seen($), t.asked.length]).toEqual(['1k', 1])
  expect(await turn($)).toEqual({ text: 'done' })
  await t.clock.settle()
  expect([await seen($), t.asked.length]).toEqual(['20k', 2])
})

test('a failed refresh clears the band and logs; the next one restores it', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  expect(await seen($)).toBe('1k')
  t.answers.push({ deny: 'usage unavailable' })
  expect(await turn($)).toEqual({ text: 'done' })
  await t.clock.settle()
  expect(await seen($)).toBe('engine')
  expect(t.logs.some(l => l.includes('context-bar: refresh failed') && l.includes('usage unavailable'))).toBe(true)
  t.answers.push(reading(30))
  await turn($)
  await t.clock.settle()
  expect(await seen($)).toBe('30k')
})

test('a breakdown with no used row, or none at all, clears the band', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  expect(await seen($)).toBe('1k')
  t.answers.push(usage({ categories: [row('Free space', 10, 'free')] }))
  await turn($)
  await t.clock.settle()
  expect(await seen($)).toBe('engine')
  t.answers.push(reading(2), usage(null))
  await turn($)
  await t.clock.settle()
  expect(await seen($)).toBe('2k')
  await turn($)
  await t.clock.settle()
  expect(await seen($)).toBe('engine')
})

test('a main-loop compaction steps aside while it runs, then draws fresh', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  expect(await seen($)).toBe('1k')
  const running = deferred<SessionCompactResult>()
  t.cfg.compact = running.promise
  t.cfg.fallback = reading(40)
  const done = compact($)
  await t.clock.settle()
  expect(await seen($)).toBe('engine')
  running.resolve(COMPACTED)
  expect(await done).toEqual(COMPACTED)
  await t.clock.settle()
  expect(await seen($)).toBe('40k')
})

test('a precompute or a subagent compaction changes nothing', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  t.cfg.fallback = reading(50)
  for (const [trigger, agentId] of [['precompute', undefined], ['manual', 'agent-1']] as const) {
    const running = deferred<SessionCompactResult>()
    t.cfg.compact = running.promise
    const done = compact($, trigger, agentId)
    await t.clock.settle()
    expect([trigger, await seen($)]).toEqual([trigger, '1k'])
    running.resolve(COMPACTED)
    await done
    await t.clock.settle()
    expect([trigger, await seen($), t.asked.length]).toEqual([trigger, '1k', 1])
  }
})

test('a vetoed compaction returns its skip unchanged and refreshes', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  t.cfg.compact = { skip: 'reason' }
  t.cfg.fallback = reading(60)
  expect(await compact($)).toEqual({ skip: 'reason' })
  await t.clock.settle()
  expect(await seen($)).toBe('60k')
})

test('hooks return while usage() is pending, and a usage() that never settles blocks nothing', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  const slow = deferred<Answer>()
  t.answers.push(slow.promise, slow.promise, slow.promise)
  expect(await turn($)).toEqual({ text: 'done' })
  expect(await compact($)).toEqual(COMPACTED)
  expect(await command($, 'on')).toEqual({ text: 'Context bar on.' })
  expect(t.asked.length).toBe(4)
  // Never settles: every later hook still answers.
  t.cfg.fallback = new Promise<Answer>(() => {}) as unknown as Answer
  expect(await turn($)).toEqual({ text: 'done' })
  expect(await compact($)).toEqual(COMPACTED)
  expect(await command($, 'off')).toEqual({ text: 'Context bar off.' })
  slow.resolve(reading(70))
  await t.clock.settle()
})

test('a refresh started before a compaction and landing after it is discarded', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  const old = deferred<Answer>()
  t.answers.push(old.promise, reading(80))
  await turn($)
  await compact($)
  await t.clock.settle()
  expect(await seen($)).toBe('80k')
  old.resolve(reading(10))
  await t.clock.settle()
  expect(await seen($)).toBe('80k')
  expect(t.commits).toEqual([1, null, 80])
})

test('a refresh that lands after /context-bar off stays hidden', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  const old = deferred<Answer>()
  t.answers.push(old.promise)
  await turn($)
  await command($, 'off')
  old.resolve(reading(10))
  await t.clock.settle()
  expect(await seen($)).toBe('engine')
  expect(t.commits).toEqual([1, null])
})

test('overlapping refreshes resolved out of order: the later-started wins', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  const first = deferred<Answer>()
  const second = deferred<Answer>()
  t.answers.push(first.promise, second.promise)
  await turn($)
  await turn($)
  second.resolve(reading(22))
  await t.clock.settle()
  first.resolve(reading(11))
  await t.clock.settle()
  expect(await seen($)).toBe('22k')
  expect(t.commits).toEqual([1, 22])
})

test('held write, then a compaction: commits are old, null, new', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  const release = t.hold()
  t.answers.push(reading(10), reading(20))
  await turn($)
  await t.clock.settle()
  // The compaction and its hook still return while the write is held.
  expect(await compact($)).toEqual(COMPACTED)
  await t.clock.settle()
  expect(t.commits).toEqual([1])
  release()
  await t.clock.settle()
  expect(t.commits).toEqual([1, 10, null, 20])
  expect(await seen($)).toBe('20k')
})

test('held write, then /context-bar off: the band hides at once and null commits last', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  const release = t.hold()
  t.answers.push(reading(10))
  await turn($)
  await t.clock.settle()
  expect(await command($, 'off')).toEqual({ text: 'Context bar off.' })
  expect(await seen($)).toBe('engine')
  release()
  await t.clock.settle()
  expect(t.commits).toEqual([1, 10, null])
  expect(await seen($)).toBe('engine')
})

test('held write while a newer refresh lands: the newer commits after it', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  const release = t.hold()
  t.answers.push(reading(10), reading(20))
  await turn($)
  await t.clock.settle()
  await turn($)
  await t.clock.settle()
  expect(t.commits).toEqual([1])
  release()
  await t.clock.settle()
  expect(t.commits).toEqual([1, 10, 20])
  expect(await seen($)).toBe('20k')
})

test('a reading queued behind a held write is dropped when a compaction lands first', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  const release = t.hold()
  t.answers.push(reading(10), reading(20), reading(30))
  await turn($)
  await t.clock.settle()
  // 20k waits in the queue behind the held 10k; the compaction then moves
  // the epoch, so 20k must never commit.
  await turn($)
  await t.clock.settle()
  await compact($)
  await t.clock.settle()
  release()
  await t.clock.settle()
  expect(t.commits).toEqual([1, 10, null, 30])
  expect(await seen($)).toBe('30k')
})

test('a survey or fewer than 20 columns makes the band pass through', async ($, on) => {
  const t = engine(on, { isOn: true })
  await start($)
  await t.clock.settle()
  expect(await seen($)).toBe('1k')
  expect(await seen($, { hasSurvey: true })).toBe('engine')
  expect(await seen($, { bodyColumns: 19 })).toBe('engine')
  const ui = await $.ui.mount({ ...BAND, props: { ...BAND.props, bodyColumns: 20 }, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('◆ 1k/1M ' + '█'.repeat(12))
  await ui.unmount()
})
