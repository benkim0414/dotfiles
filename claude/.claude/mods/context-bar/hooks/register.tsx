import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Reading } from '../types'
import { layout, reduce } from './layout'

const USAGE = 'Usage: /context-bar [on|off]'

// Mirrors $.store's isOn (R15), so the render hook reads state only.
const isOn = atom({ plugin: 'context-bar', key: 'isOn' } as const, false)
// Change the tag when Reading changes: it declines what an earlier version
// stored, which outlives a reload.
const reading = atom({ plugin: 'context-bar', key: 'reading' } as const, null, {
  shape: 'reading-2',
})

// R13: starting a refresh, a compaction's clear and turning the bar off
// each move the epoch; every write to the reading goes through `queue`.
// Module variables, so a reload starts them over (spec concern 5).
let epoch = 0
let queue: Promise<void> = Promise.resolve()

// One write at a time. A refresh's write (`mine` set) checks its epoch at
// the head of the queue, immediately before the write, and is dropped if
// the epoch has moved; nothing else writes the reading in between.
function publish($: EngineInterface, value: Reading | null, mine?: number): Promise<void> {
  queue = queue.then(async () => {
    if (mine !== undefined && mine !== epoch) return
    try {
      await update($, reading, () => value)
    } catch (err) {
      $.ui.log(`context-bar: state write failed: ${err}`, { to: 'debug' })
    }
  })
  return queue
}

// Queued, never awaited: a held write delays no compaction or command.
function clear($: EngineInterface): void {
  epoch++
  void publish($, null)
}

// R10, R12: started with `void`, so nothing may escape it.
async function refresh($: EngineInterface): Promise<void> {
  const mine = ++epoch
  let next: Reading | null = null
  try {
    next = reduce(await $.session.usage({ breakdown: 'summary' }))
  } catch (err) {
    $.ui.log(`context-bar: refresh failed: ${err}`, { to: 'debug' })
  }
  await publish($, next, mine)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await $.command.register({
      name: 'context-bar',
      description: 'Show or hide the context breakdown above the prompt: [on|off]',
    })
    const stored = (await $.store.get('isOn')) === true
    await update($, isOn, () => stored)
    if (stored) void refresh($)
    return result
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && (await read($, isOn))) void refresh($)
    return result
  })

  // R9, R11: a main-loop compaction clears first and refreshes after, even
  // when it was vetoed with { skip }.
  on('session.compact', async ($, e, next) => {
    if (e.agentId !== undefined || e.trigger === 'precompute') return next(e)
    clear($)
    const result = await next(e)
    if (await read($, isOn)) void refresh($)
    return result
  })

  // R14, R15.
  on('command.run', { command: 'context-bar' }, async ($, e) => {
    const arg = e.args.trim()
    if (arg !== '' && arg !== 'on' && arg !== 'off') return { text: USAGE }
    const isTurnedOn = arg === '' ? !(await read($, isOn)) : arg === 'on'
    await $.store.set('isOn', isTurnedOn)
    await update($, isOn, () => isTurnedOn)
    if (isTurnedOn) void refresh($)
    else clear($)
    return { text: isTurnedOn ? 'Context bar on.' : 'Context bar off.' }
  })

  // R8: step aside for a survey, while off, with no reading, or under 20
  // columns; otherwise draw the band layout gives, framed from 60 (R7).
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || !(await read($, isOn))) return next(e)
    const value = await read($, reading)
    const band = value && layout(value, e.props.bodyColumns)
    if (!band) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const frame = band.isFramed ? { borderStyle: 'round', borderColor: 'inactive', paddingX: 1 } : {}
    return (
      <Box flexDirection="column" {...frame}>
        {band.rows.map(row => (
          <Text>
            {row.map(s => (
              <Text color={s.color} dimColor={s.dim} bold={s.bold} backgroundColor={s.background}>
                {s.text}
              </Text>
            ))}
          </Text>
        ))}
      </Box>
    )
  })
}
