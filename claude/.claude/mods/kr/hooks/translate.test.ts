import { expect, test } from 'claude-code/testing'
import type { EngineInterface, ModelCompleteRequest, ModelCompleteResult, ModelTextBlock } from 'claude-code'

import { codeEqual, fnv1a32, numbered, protect, restore, split, translate } from './translate'

const USAGE = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }

// Stands in for `$`: only `model.complete`, recording each request and
// answering it with `reply`. A test plugin cannot hand its `$` to an imported
// helper (the engine refuses it), so translate meets this fake instead.
function model(reply: (req: ModelCompleteRequest) => ModelCompleteResult) {
  const calls: ModelCompleteRequest[] = []
  const complete = async (req: ModelCompleteRequest) => {
    calls.push(req)
    return reply(req)
  }
  return { calls, run: (source: string, timeoutMs = 10_000) => translate({ model: { complete } } as unknown as EngineInterface, source, timeoutMs) }
}

const answer = (text: string): ModelCompleteResult => ({ isAnswered: true, text, usage: USAGE })
const promptOf = (req: ModelCompleteRequest) => (typeof req.prompt === 'string' ? req.prompt : req.prompt.map(b => b.text).join(''))

const FENCED = [
  'Run this:',
  '',
  '```sh',
  'git status',
  '```',
  '',
  'Or with tildes:',
  '',
  '~~~',
  'echo `hi`',
  '~~~',
].join('\n')

const NESTED = ['Example:', '', '````md', '```sh', 'ls', '```', '````', '', 'Done.'].join('\n')

const INLINE = 'Edit `register.tsx` and call ``a ` b`` from `on`.'

test('protect and restore round-trip byte for byte', () => {
  for (const source of [FENCED, NESTED, INLINE, FENCED.replaceAll('\n', '\r\n'), INLINE + '\r\n\r\n' + NESTED.replaceAll('\n', '\r\n')]) {
    const { text, spans } = protect(source)
    expect(text.includes('`') || text.includes('~~~'), `code left in ${JSON.stringify(text)}`).toBe(false)
    expect(restore(text, spans)).toEqual({ ok: true, text: source })
  }
})

test('placeholders are numbered in order, and a nested fence is part of its outer one', () => {
  expect(protect(FENCED).spans).toEqual(['```sh\ngit status\n```', '~~~\necho `hi`\n~~~'])
  expect(protect(NESTED).spans).toEqual(['````md\n```sh\nls\n```\n````'])
  expect(protect(INLINE)).toEqual({
    text: 'Edit ⟦K0⟧ and call ⟦K1⟧ from ⟦K2⟧.',
    spans: ['`register.tsx`', '``a ` b``', '`on`'],
  })
})

test('an unmatched backtick is text, and a code span ends at a blank line', () => {
  expect(protect('a ` b\n\nc ` d').spans).toEqual([])
  expect(protect('one `two`\nthree').spans).toEqual(['`two`'])
})

test('a reply that drops, duplicates or alters a placeholder fails code-changed', () => {
  const { spans } = protect(INLINE)
  const failed = { ok: false, reason: 'code-changed' }
  expect(restore('⟦K0⟧ ⟦K1⟧ ⟦K2⟧', spans)).toEqual({ ok: true, text: spans.join(' ') })
  expect(restore('⟦K0⟧ ⟦K2⟧', spans)).toEqual(failed)
  expect(restore('⟦K0⟧ ⟦K1⟧ ⟦K1⟧ ⟦K2⟧', spans)).toEqual(failed)
  expect(restore('⟦K0⟧ ⟦K 1⟧ ⟦K2⟧', spans)).toEqual(failed)
  expect(restore('⟦K0⟧ ⟦K1⟧ ⟦K2⟧ ⟦K3⟧', spans)).toEqual(failed)
})

test('codeEqual compares fenced blocks and inline spans in order', () => {
  expect(codeEqual(FENCED, FENCED.replace('Run this:', '이것을 실행:'))).toBe(true)
  expect(codeEqual(FENCED, FENCED.replace('git status', 'git log'))).toBe(false)
  expect(codeEqual(INLINE, INLINE.replace('`on`', '`off`'))).toBe(false)
  expect(codeEqual(INLINE, 'Edit `register.tsx` from `on`.')).toBe(false)
})

test('numbered fields split back by number', () => {
  const fields = ['Which one?', 'Fast', 'Uses `haiku`.\n\nTwo lines.']
  expect(split(numbered(fields), 3)).toEqual({ ok: true, parts: fields })
  expect(split(numbered(fields), 4)).toEqual({ ok: false, reason: 'count-mismatch' })
  expect(split(numbered(fields).replace('⟦N2⟧', '⟦N4⟧'), 3)).toEqual({ ok: false, reason: 'count-mismatch' })
  expect(split('preamble\n' + numbered(fields), 3)).toEqual({ ok: false, reason: 'count-mismatch' })
})

test('fnv1a32 matches the reference values', () => {
  expect([fnv1a32(''), fnv1a32('a'), fnv1a32('foobar')]).toEqual(['811c9dc5', 'e40c292c', 'bf9cf968'])
})

test('translate asks haiku with a cached system block and a capped maxTokens', async () => {
  const { calls, run } = model(req => answer(promptOf(req).replace('Edit', '편집')))
  expect(await run(INLINE)).toEqual({ ok: true, text: INLINE.replace('Edit', '편집') })
  const long = 'x'.repeat(7000)
  await run(long, 30_000)

  expect(calls.length).toBe(2)
  const [first, second] = calls
  expect(first?.model).toBe('haiku')
  expect(first?.prompt).toBe('Edit ⟦K0⟧ and call ⟦K1⟧ from ⟦K2⟧.')
  const system = first?.system as readonly ModelTextBlock[]
  expect(system.length).toBe(1)
  expect(system[0]?.cache).toBe(true)
  expect(system[0]?.text).toContain('⟦K<n>⟧')
  expect(first?.maxTokens).toBe(4 * Math.ceil(INLINE.length / 3))
  expect(first?.timeoutMs).toBe(10_000)
  expect(second?.maxTokens).toBe(8192)
  expect(second?.timeoutMs).toBe(30_000)
})

test('each unanswered reason comes back as the failure reason', async () => {
  const results: ModelCompleteResult[] = [
    { isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded', usage: USAGE },
    { isAnswered: false, reason: 'api-error', status: null, error: 'unknown', usage: USAGE },
    { isAnswered: false, reason: 'empty-reply', usage: USAGE },
    { isAnswered: false, reason: 'aborted', usage: USAGE },
  ]
  const { calls, run } = model(() => results[calls.length - 1]!)
  const reasons = []
  for (const _ of results) reasons.push(await run('Hello.'))
  expect(reasons).toEqual([
    { ok: false, reason: 'api-error 529' },
    { ok: false, reason: 'api-error' },
    { ok: false, reason: 'empty-reply' },
    { ok: false, reason: 'aborted' },
  ])
})

test('a reply with a control character other than tab or newline fails control-char', async () => {
  let reply = '안녕\t하세요\n'
  const { calls, run } = model(() => answer(reply))
  expect(await run('Hello.')).toEqual({ ok: true, text: reply })
  reply = '안녕\x1b[31m하세요'
  expect(await run('Hello.')).toEqual({ ok: false, reason: 'control-char' })
  expect(calls.length).toBe(2)
})

test('a reply that loses a placeholder fails code-changed', async () => {
  const { run } = model(() => answer('편집 ⟦K0⟧ 그리고 ⟦K2⟧.'))
  expect(await run(INLINE)).toEqual({ ok: false, reason: 'code-changed' })
})

test('a source holding ⟦K is sent unprotected and checked by codeEqual', async () => {
  const source = 'Literal ⟦K0⟧ and `code`.'
  let reply = '문자 ⟦K0⟧ 그리고 `code`.'
  const { calls, run } = model(() => answer(reply))
  expect(await run(source)).toEqual({ ok: true, text: reply })
  expect(calls[0] && promptOf(calls[0])).toBe(source)
  reply = '문자 ⟦K0⟧ 그리고 `코드`.'
  expect(await run(source)).toEqual({ ok: false, reason: 'code-changed' })
})
