// Test fixtures shared by layout.test.ts and register.test.tsx; the hooks
// module never imports this file.

import type { ContextCategory, ContextCategoryKind, SessionUsage } from 'claude-code'

export const row = (
  name: string,
  tokens: number,
  kind: ContextCategoryKind = 'used',
  color = 'claude',
): ContextCategory => ({ name, tokens, color, kind, isDeferred: kind === 'deferred' })

// The intent's example: 90.3k used + 896.7k free + 13k reserved = 1M.
export const EXAMPLE: ContextCategory[] = [
  row('System prompt', 4200, 'used', 'promptBorder'),
  row('System tools', 17_000, 'used', 'inactive'),
  row('MCP tools', 52_000, 'used', 'suggestion'),
  row('Custom agents', 3400, 'used', 'permission'),
  row('Memory files', 8600, 'used', 'claude'),
  row('Skills', 5100, 'used', 'warning'),
  row('Messages', 0, 'used', 'merged'),
  row('MCP tools (deferred)', 40_000, 'deferred', 'inactive'),
  row('Free space', 896_700, 'free', 'promptBorder'),
  row('Autocompact buffer', 13_000, 'buffer', 'inactive'),
]

export type Breakdown = {
  categories?: ContextCategory[]
  totalTokens?: number
  rawMaxTokens?: number
  autoCompactThreshold?: number
  isAutoCompactEnabled?: boolean
}

// A SessionUsage carrying a breakdown, or none when `b` is null.
export function usage(b: Breakdown | null = {}): SessionUsage {
  const categories = b?.categories ?? EXAMPLE
  const used = categories.filter(c => c.kind === 'used').reduce((a, c) => a + c.tokens, 0)
  const window = b?.rawMaxTokens ?? 1_000_000
  return {
    startedAt: 0,
    rateLimits: [],
    context: {
      window,
      ...(b === null
        ? {}
        : {
            breakdown: {
              categories,
              totalTokens: b.totalTokens ?? used,
              maxTokens: window,
              rawMaxTokens: window,
              autocompactSource: 'model-default',
              percentage: Math.round(((b.totalTokens ?? used) / window) * 100),
              gridRows: [],
              model: 'test',
              memoryFiles: [],
              mcpTools: [],
              agents: [],
              isAutoCompactEnabled: b.isAutoCompactEnabled ?? true,
              ...((b.isAutoCompactEnabled ?? true)
                ? { autoCompactThreshold: b.autoCompactThreshold ?? 987_000 }
                : {}),
              apiUsage: null,
            },
          }),
    },
  } as SessionUsage
}
