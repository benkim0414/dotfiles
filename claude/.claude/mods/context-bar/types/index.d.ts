// One segment of the bar and one legend entry: a breakdown row reduced to
// what the layout needs. `color` is the row's theme key.
export type Part = { label: string; tokens: number; color: string }

// The breakdown reduced (spec "Reading"): every figure shares `window`.
export type Reading = {
  // kind 'used', in /context order
  used: Part[]
  // kind 'free', or 0 tokens when the row is missing
  free: Part
  // kind 'buffer'; null when absent
  reserved: Part | null
  totalTokens: number
  // rawMaxTokens
  window: number
  // percent of the window, or null when auto-compact is off
  compactsAt: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'context-bar': {
      // Mirrors $.store's isOn, which is the source of truth across sessions.
      isOn: boolean
      reading: Shaped<Reading | null>
    }
  }
}
