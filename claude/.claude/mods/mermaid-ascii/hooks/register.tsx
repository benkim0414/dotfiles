import { update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Art } from '../types'
import { displayWidth, fenceFor, fnv1a32, isMermaid, scanFences } from './text'

// Columns the terminal indents an assistant reply by (spec concern 4).
const REPLY_INDENT = 2
const SETUP = 'npm ci --prefix ~/workspace/dotfiles/claude/.claude/mods/mermaid-ascii/render'
const WARNED = { plugin: 'mermaid-ascii', key: 'warnedMissing' } as const

export const register: Register = on => {
  // Each id's first claimant this load, id to full source: one owner per id,
  // so a hash collision never converts the second source (spec step 4).
  const claims = new Map<string, string>()

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    if (e.surface !== 'terminal') return next(e)
    const fences = scanFences(e.props.text).filter(f => isMermaid(f.info))
    if (fences.length === 0) return next(e)

    const room = e.viewport ? e.viewport.columns - REPLY_INDENT : Infinity
    const lines = e.props.text.split('\n')
    let isChanged = false
    // Last block first, so earlier line indexes still hold after a splice.
    for (const f of [...fences].reverse()) {
      const id = fnv1a32(f.source)
      const { value } = await $.state.get({ plugin: 'mermaid-ascii', key: 'art', id })
      if (value === undefined) {
        if (!claims.has(id)) {
          claims.set(id, f.source)
          $.clock.after(0, () => void convert($, id, f.source))
        }
        continue
      }
      if (value.source !== f.source || !value.ok) continue
      const art = value.art.split('\n').map(l => f.indent + l)
      if (art.some(l => displayWidth(l) > room)) continue
      const ticks = f.indent + fenceFor(value.art)
      lines.splice(f.start, f.end - f.start + 1, `${ticks}text`, ...art, ticks)
      isChanged = true
    }
    if (!isChanged) return next(e)
    return next({ ...e, props: { ...e.props, text: lines.join('\n') } })
  })
}

// Runs outside drawing. Keeps a value already written, so the first result
// for an id owns it even across a reload (spec step 5).
async function convert($: EngineInterface, id: string, source: string): Promise<void> {
  const result = await run($, source)
  await update($, { plugin: 'mermaid-ascii', key: 'art', id }, prev => prev ?? result)
}

async function run($: EngineInterface, source: string): Promise<Art> {
  const failed: Art = { source, ok: false }
  // render.mjs runs from its real path so node finds node_modules in the
  // repo checkout, however Stow linked ~/.claude/mods.
  const root = `${$.plugin.root}/render`
  const dir = (await $.fs.stat(root, { resolve: true }).catch(() => undefined))?.realPath ?? root
  let r
  try {
    r = await $.process.run(['node', `${dir}/render.mjs`], { cwd: dir, stdin: source, timeoutMs: 5000 })
  } catch (err) {
    // ENOENT: node cannot start. Anything else is taken as a timeout.
    if (/ENOENT/.test(String((err as { code?: unknown })?.code ?? err))) await warnMissing($)
    return failed
  }
  if (r.exitCode === 3) await warnMissing($)
  if (r.exitCode !== 0) return failed
  const art = r.stdout.split('\n').map(l => l.trimEnd()).join('\n').trimEnd()
  return art === '' ? failed : { source, ok: true, art }
}

// One toast per session: the versioned write lets one failing block win.
async function warnMissing($: EngineInterface): Promise<void> {
  const { value, version } = await $.state.get(WARNED)
  if (value) return
  const { isSet } = await $.state.set(WARNED, true, { ifVersion: version })
  if (isSet) $.ui.toast(`mermaid-ascii: converter not installed. Run: ${SETUP}`)
}
