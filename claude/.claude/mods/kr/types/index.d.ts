// A translation, keyed by the hash of its source. `source` is kept so a hash
// collision draws English alone instead of another text's Korean.
export type Ko = { source: string; ok: true; text: string } | { source: string; ok: false; reason: string }

declare module 'claude-code' {
  interface PluginState {
    kr: {
      isOn: boolean
      // A main-loop model request is streaming.
      inFlight: boolean
      // The last first-draw number handed out.
      seq: number
      // By message id: its first-draw number.
      seen: StateFamily<number>
      // The first-draw number of the last prompt the person sent.
      lastPromptSeq: number
      // Set by /kr on, null when off; blocks first drawn above it are eligible.
      fromSeq: number | null
      // By text id; kept across off and on.
      ko: StateFamily<Ko>
      // By ExitPlanMode tool_use_id.
      plan: StateFamily<Ko>
      // This session's last plan-file write.
      planPath: string | null
    }
  }
}
