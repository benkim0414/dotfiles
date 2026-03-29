# Shell Scripting

- Always start scripts with `#!/usr/bin/env bash` and `set -euo pipefail`
- Quote all variable expansions: `"$var"` not `$var`
- Use `[[ ]]` for conditionals and `local` for function-scoped variables
- Provide a usage/help message; exit 1 on invalid arguments
- Log messages to stderr (`>&2`); reserve stdout for pipeline-consumable data
- ShellCheck must pass with no warnings before committing any script
- Prefer clarity over cleverness; scripts are read under pressure during incidents
