// A block's conversion result, keyed by fnv1a32(source). `source` is kept so
// a hash collision is never mistaken for a hit.
export type Art =
  | { source: string; ok: true; art: string }
  | { source: string; ok: false }

declare module 'claude-code' {
  interface PluginState {
    'mermaid-ascii': {
      art: StateFamily<Art>
      // The missing-converter toast has been shown this session.
      warnedMissing: boolean
    }
  }
}
