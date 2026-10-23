import type { Register } from 'claude-code'

export const register: Register = on => {
  on('ui.render', { component: 'AssistantMessage' }, ($, e, next) => next(e))
}
