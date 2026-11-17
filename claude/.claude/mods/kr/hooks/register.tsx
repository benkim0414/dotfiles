import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import { GUTTER, INDENT, layoutFor } from './layout'
import { fnv1a32, translate } from './translate'

const USAGE = 'Usage: /kr [on|off]'
// How long one reply's translation may take.
const REPLY_TIMEOUT_MS = 30_000
// The rule between English and Korean when stacked with no viewport.
const RULE_WIDTH = 40

const isOn = atom({ plugin: 'kr', key: 'isOn' } as const, false)
const inFlight = atom({ plugin: 'kr', key: 'inFlight' } as const, false)
const seq = atom({ plugin: 'kr', key: 'seq' } as const, 0)
const lastPromptSeq = atom({ plugin: 'kr', key: 'lastPromptSeq' } as const, 0)
const fromSeq = atom({ plugin: 'kr', key: 'fromSeq' } as const, null)

// The /kr command's own row is not a prompt: counting it would move the
// boundary past the reply /kr on is meant to show.
const KR_COMMAND = /^\/kr(\s|$)/

// Module claims, so a redraw never schedules the same work twice. A reload
// starts them over; the state they guard does not.
const noting = new Set<string>()
// Text id to the source that claimed it: a hash collision never translates
// the second source.
const claims = new Map<string, string>()

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await $.command.register({
      name: 'kr',
      description: 'Show replies in Korean beside English (this session)',
      argumentHint: '[on|off]',
    })
    return result
  })

  // R1, R2, R12. Turning on takes the latest prompt as the boundary; on
  // while on keeps it, so nothing eligible turns back to English.
  on('command.run', { command: 'kr' }, async ($, e) => {
    const arg = e.args.trim()
    if (arg !== '' && arg !== 'on' && arg !== 'off') return { text: USAGE }
    const wasOn = await read($, isOn)
    const isTurnedOn = arg === '' ? !wasOn : arg === 'on'
    if (isTurnedOn && !wasOn) {
      const boundary = await read($, lastPromptSeq)
      await update($, fromSeq, () => boundary)
    }
    if (!isTurnedOn) await update($, fromSeq, () => null)
    await update($, isOn, () => isTurnedOn)
    return { text: isTurnedOn ? 'kr: on' : 'kr: off' }
  })

  // R10: while a main-loop request streams, its blocks are not final.
  on('turn.step', async function* ($, e, next) {
    if (e.agentId !== undefined) return yield* next(e)
    await update($, inFlight, () => true)
    try {
      return yield* next(e)
    } finally {
      await update($, inFlight, () => false)
    }
  })

  // Every surface: a row drawn only on desktop still counts as drawn.
  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    const isPrompt = (e.props.origin.kind === 'composer' || e.props.origin.kind === 'bridge') && !KR_COMMAND.test(e.props.text)
    await firstDraw($, e.requestId, isPrompt)
    return next(e)
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const n = await firstDraw($, e.requestId, false)
    if (e.surface !== 'terminal' || n === undefined) return next(e)
    const boundary = await read($, fromSeq)
    if (!(await read($, isOn)) || boundary === null || n <= boundary) return next(e)

    const text = e.props.text
    const id = fnv1a32(text)
    const claimant = claims.get(id)
    if (claimant !== undefined && claimant !== text) return next(e)
    const { value: cached } = await $.state.get({ plugin: 'kr', key: 'ko', id })
    if (cached !== undefined && cached.source !== text) return next(e)
    if (cached === undefined && claimant === undefined && !(await read($, inFlight))) {
      claims.set(id, text)
      $.clock.after(0, () => void work($, id, text))
    }

    const { Box, Text, Markdown } = $.ui.resolve(e)
    const korean =
      cached === undefined ? <Text dimColor>번역 중…</Text>
      : cached.ok ? <Markdown text={cached.text} />
      : <Text dimColor>{`번역 실패 (${cached.reason})`}</Text>
    const layout = layoutFor(e.viewport?.columns)
    if (layout.mode === 'side') {
      return (
        <Box flexDirection="row" columnGap={GUTTER}>
          <Box width={layout.colWidth} flexShrink={0}>
            <Markdown text={text} />
          </Box>
          <Box width={layout.colWidth} flexShrink={0}>
            {korean}
          </Box>
        </Box>
      )
    }
    const rule = e.viewport ? Math.max(1, e.viewport.columns - INDENT) : RULE_WIDTH
    return (
      <Box flexDirection="column">
        <Markdown text={text} />
        <Text dimColor>{'─'.repeat(rule)}</Text>
        {korean}
      </Box>
    )
  })
}

// The row's first-draw number, or undefined on a first draw, which
// schedules `note` (a render hook never writes state).
async function firstDraw($: EngineInterface, requestId: string, isPrompt: boolean): Promise<number | undefined> {
  const { value } = await $.state.get({ plugin: 'kr', key: 'seen', id: requestId })
  if (value === undefined && !noting.has(requestId)) {
    noting.add(requestId)
    $.clock.after(0, () => void note($, requestId, isPrompt))
  }
  return value
}

// Hands out the next first-draw number; a prompt also moves the boundary.
async function note($: EngineInterface, requestId: string, isPrompt: boolean): Promise<void> {
  const { value } = await $.state.get({ plugin: 'kr', key: 'seen', id: requestId })
  if (value !== undefined) return
  const n = await update($, seq, s => s + 1)
  await update($, { plugin: 'kr', key: 'seen', id: requestId }, prev => prev ?? n)
  if (isPrompt) await update($, lastPromptSeq, () => n)
}

// Runs outside drawing. The first result for a text id owns it.
async function work($: EngineInterface, id: string, source: string): Promise<void> {
  const r = await translate($, source, REPLY_TIMEOUT_MS)
  await update($, { plugin: 'kr', key: 'ko', id }, prev => prev ?? { source, ...r })
}
