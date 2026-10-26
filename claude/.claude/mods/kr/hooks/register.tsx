import type { Register } from 'claude-code'

// Step 2 scaffold: draws nothing of its own yet.
export const register: Register = on => {
  on('ui.render', { component: 'AssistantMessage' }, ($, e, next) => next(e))
}
