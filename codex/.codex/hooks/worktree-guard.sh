#!/usr/bin/env bash
# set -euo pipefail
#
# input="$(cat)"
# tool_name="$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null || true)"
# cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)"
#
# if [[ -z "$cwd" || ! -d "$cwd" ]]; then
#   cwd="$PWD"
# fi
#
# deny() {
#   local reason="$1"
#
#   jq -cn --arg reason "$reason" '{
#     hookSpecificOutput: {
#       hookEventName: "PreToolUse",
#       permissionDecision: "deny",
#       permissionDecisionReason: $reason
#     }
#   }'
#   exit 0
# }
#
# canonical_path() {
#   local path="$1"
#   local dir
#   local base
#
#   if [[ -d "$path" ]]; then
#     (cd "$path" && pwd -P)
#     return
#   fi
#
#   dir="$(dirname "$path")"
#   base="$(basename "$path")"
#   if [[ -d "$dir" ]]; then
#     printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
#   else
#     printf '%s\n' "$path"
#   fi
# }
#
# cwd="$(canonical_path "$cwd")"
#
# effective_cwd() {
#   local tool_workdir
#
#   tool_workdir="$(jq -r '.tool_input.workdir // .tool_input.cwd // .tool_input.current_working_directory // empty' <<<"$input" 2>/dev/null || true)"
#   if [[ -n "$tool_workdir" && -d "$tool_workdir" ]]; then
#     canonical_path "$tool_workdir"
#     return
#   fi
#
#   canonical_path "$cwd"
# }
#
# repo_root_for() {
#   local dir="${1:-$cwd}"
#
#   git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true
# }
#
# repo_root_for_path() {
#   local path="$1"
#   local dir="$path"
#
#   if [[ ! -d "$dir" ]]; then
#     dir="$(dirname "$dir")"
#   fi
#
#   while [[ ! -d "$dir" && "$dir" != "/" && "$dir" != "." ]]; do
#     dir="$(dirname "$dir")"
#   done
#
#   if [[ ! -d "$dir" ]]; then
#     return 0
#   fi
#
#   git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true
# }
#
# resolve_git_path() {
#   local path="$1"
#   local base_dir="${2:-$cwd}"
#
#   if [[ "$path" = /* ]]; then
#     canonical_path "$path"
#   else
#     canonical_path "$base_dir/$path"
#   fi
# }
#
# is_linked_worktree() {
#   local dir="${1:-$cwd}"
#   local absolute_git_dir
#   local common_git_dir
#
#   absolute_git_dir="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null || true)"
#   common_git_dir="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null || true)"
#
#   if [[ -z "$absolute_git_dir" || -z "$common_git_dir" ]]; then
#     return 1
#   fi
#
#   absolute_git_dir="$(canonical_path "$absolute_git_dir")"
#   common_git_dir="$(resolve_git_path "$common_git_dir" "$dir")"
#
#   [[ "$absolute_git_dir" != "$common_git_dir" ]]
# }
#
# primary_worktree_root_for_current_repo() {
#   local dir="${1:-$cwd}"
#   local common_git_dir
#
#   common_git_dir="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null || true)"
#   if [[ -z "$common_git_dir" ]]; then
#     return 1
#   fi
#
#   if [[ "$common_git_dir" = /* ]]; then
#     common_git_dir="$(canonical_path "$common_git_dir")"
#   else
#     common_git_dir="$(canonical_path "$dir/$common_git_dir")"
#   fi
#
#   canonical_path "$(dirname "$common_git_dir")"
# }
#
# is_linked_worktree_at() {
#   local path="$1"
#   local dir="$path"
#   local absolute_git_dir
#   local common_git_dir
#
#   if [[ ! -d "$dir" ]]; then
#     dir="$(dirname "$dir")"
#   fi
#
#   while [[ ! -d "$dir" && "$dir" != "/" && "$dir" != "." ]]; do
#     dir="$(dirname "$dir")"
#   done
#
#   if [[ ! -d "$dir" ]]; then
#     return 1
#   fi
#
#   absolute_git_dir="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null || true)"
#   common_git_dir="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null || true)"
#
#   if [[ -z "$absolute_git_dir" || -z "$common_git_dir" ]]; then
#     return 1
#   fi
#
#   absolute_git_dir="$(canonical_path "$absolute_git_dir")"
#   if [[ "$common_git_dir" = /* ]]; then
#     common_git_dir="$(canonical_path "$common_git_dir")"
#   else
#     common_git_dir="$(canonical_path "$dir/$common_git_dir")"
#   fi
#
#   [[ "$absolute_git_dir" != "$common_git_dir" ]]
# }
#
# path_is_inside() {
#   local path="$1"
#   local root="$2"
#
#   case "$path" in
#     "$root"|"$root"/*)
#       return 0
#       ;;
#     *)
#       return 1
#       ;;
#   esac
# }
#
# tool_target_path() {
#   jq -r '
#     .tool_input.file_path //
#     .tool_input.path //
#     .tool_input.target_file //
#     .tool_input.filename //
#     empty
#   ' <<<"$input" 2>/dev/null || true
# }
#
# apply_patch_target_paths() {
#   local patch
#   local line
#   local path
#
#   case "$tool_name" in
#     apply_patch|functions.apply_patch)
#       ;;
#     *)
#       return 0
#       ;;
#   esac
#
#   patch="$(jq -r '.tool_input.cmd // empty' <<<"$input" 2>/dev/null || true)"
#   while IFS= read -r line; do
#     case "$line" in
#       "*** Add File: "*)
#         path="${line#"*** Add File: "}"
#         ;;
#       "*** Update File: "*)
#         path="${line#"*** Update File: "}"
#         ;;
#       "*** Delete File: "*)
#         path="${line#"*** Delete File: "}"
#         ;;
#       "*** Move to: "*)
#         path="${line#"*** Move to: "}"
#         ;;
#       *)
#         continue
#         ;;
#     esac
#
#     if [[ -n "$path" ]]; then
#       printf '%s\n' "$path"
#     fi
#   done <<<"$patch"
# }
#
# tool_target_paths() {
#   local target
#
#   target="$(tool_target_path)"
#   if [[ -n "$target" ]]; then
#     printf '%s\n' "$target"
#   fi
#
#   apply_patch_target_paths
# }
#
# command_text() {
#   jq -r '.tool_input.command // .tool_input.cmd // .tool_input.code // .tool_input.script // .tool_input.shell // ""' <<<"$input" 2>/dev/null || true
# }
#
# mcp_executor_command_texts() {
#   jq -r '
#     [
#       .tool_input.command?,
#       .tool_input.cmd?,
#       .tool_input.code?,
#       .tool_input.script?,
#       .tool_input.shell?
#     ]
#     + (.tool_input.commands? // [] | map(.command?))
#     | .[]
#     | select(type == "string" and length > 0)
#   ' <<<"$input" 2>/dev/null || true
# }
#
# shell_words() {
#   local command="$1"
#   local output_name="$2"
#   local -n output="$output_name"
#   local char
#   local next_char
#   local quote=""
#   local token=""
#   local in_token=0
#   local i=0
#   local length="${#command}"
#
#   output=()
#   while (( i < length )); do
#     char="${command:i:1}"
#
#     if [[ -n "$quote" ]]; then
#       case "$quote" in
#         "'")
#           if [[ "$char" == "'" ]]; then
#             quote=""
#           else
#             token+="$char"
#           fi
#           ;;
#         '"')
#           case "$char" in
#             '"')
#               quote=""
#               ;;
#             "\\")
#               ((i++))
#               if (( i >= length )); then
#                 token+="\\"
#                 break
#               fi
#               next_char="${command:i:1}"
#               case "$next_char" in
#                 '$'|'`'|'"'|"\\"|$'\n')
#                   token+="$next_char"
#                   ;;
#                 *)
#                   token+="\\$next_char"
#                   ;;
#               esac
#               ;;
#             *)
#               token+="$char"
#               ;;
#           esac
#           ;;
#       esac
#     else
#       case "$char" in
#         [[:space:]])
#           if [[ "$in_token" -eq 1 ]]; then
#             output+=("$token")
#             token=""
#             in_token=0
#           fi
#           ;;
#         "'")
#           quote="'"
#           in_token=1
#           ;;
#         '"')
#           quote='"'
#           in_token=1
#           ;;
#         "\\")
#           in_token=1
#           ((i++))
#           if (( i >= length )); then
#             token+="\\"
#             break
#           fi
#           token+="${command:i:1}"
#           ;;
#         *)
#           token+="$char"
#           in_token=1
#           ;;
#       esac
#     fi
#
#     ((i++))
#   done
#
#   if [[ -n "$quote" ]]; then
#     return 1
#   fi
#
#   if [[ "$in_token" -eq 1 ]]; then
#     output+=("$token")
#   fi
#
#   return 0
# }
#
# has_unresolved_git_c_option() {
#   local command="$1"
#   local -a words
#
#   case "$command" in
#     git[[:space:]]*-C*|git[[:space:]]*--git-dir*|git[[:space:]]*--work-tree*)
#       ;;
#     *)
#       return 1
#       ;;
#   esac
#
#   if shell_words "$command" words; then
#     return 1
#   fi
#
#   return 0
# }
#
# main_worktree_root_for_path() {
#   local path="$1"
#   local target_path
#   local target_repo_root
#
#   case "$path" in
#     /*)
#       target_path="$(canonical_path "$path")"
#       ;;
#     *)
#       return 1
#       ;;
#   esac
#
#   target_repo_root="$(repo_root_for_path "$target_path")"
#   if [[ -z "$target_repo_root" ]]; then
#     return 1
#   fi
#   target_repo_root="$(canonical_path "$target_repo_root")"
#
#   if ! path_is_inside "$target_path" "$target_repo_root"; then
#     return 1
#   fi
#
#   if is_linked_worktree_at "$target_path"; then
#     return 1
#   fi
#
#   printf '%s\n' "$target_repo_root"
# }
#
# main_worktree_root_for_target() {
#   local target="$1"
#   local target_path
#   local target_repo_root
#
#   case "$target" in
#     /*)
#       target_path="$(canonical_path "$target")"
#       ;;
#     *)
#       target_path="$(canonical_path "$cwd/$target")"
#       ;;
#   esac
#
#   target_repo_root="$(repo_root_for_path "$target_path")"
#   if [[ -z "$target_repo_root" ]]; then
#     return 1
#   fi
#   target_repo_root="$(canonical_path "$target_repo_root")"
#
#   if ! path_is_inside "$target_path" "$target_repo_root"; then
#     return 1
#   fi
#
#   if is_linked_worktree_at "$target_path"; then
#     return 1
#   fi
#
#   printf '%s\n' "$target_repo_root"
# }
#
# command_referenced_main_worktree_root() {
#   local command="$1"
#   local base_dir="${2:-$cwd}"
#   local -a words
#   local word
#   local candidate
#   local root
#
#   shell_words "$command" words || return 1
#
#   for word in "${words[@]}"; do
#     word="${word%\"}"
#     word="${word#\"}"
#     word="${word%\'}"
#     word="${word#\'}"
#     if [[ "$word" =~ ^[0-9]*(>>|>|<)(.*)$ ]]; then
#       word="${BASH_REMATCH[2]}"
#       word="${word%\"}"
#       word="${word#\"}"
#       word="${word%\'}"
#       word="${word#\'}"
#     fi
#     word="${word%;}"
#     word="${word#;}"
#     word="${word%&}"
#     word="${word#&}"
#     word="${word%|}"
#     word="${word#|}"
#     word="${word%)}"
#     word="${word#(}"
#     case "$word" in
#       '$HOME'/*)
#         word="${HOME}${word#\$HOME}"
#         ;;
#       '${HOME}'/*)
#         word="${HOME}${word#\$\{HOME\}}"
#         ;;
#       "~"/*)
#         word="${HOME}${word#\~}"
#         ;;
#     esac
#     case "$word" in
#       /*)
#         candidate="$word"
#         ;;
#       ./*|../*|*/*)
#         candidate="$base_dir/$word"
#         ;;
#       *)
#         continue
#         ;;
#     esac
#
#     root="$(main_worktree_root_for_path "$candidate" || true)"
#     if [[ -n "$root" ]]; then
#       printf '%s\n' "$root"
#       return 0
#     fi
#   done
#
#   return 1
# }
#
# command_targets_outside_git_repo() {
#   local command="$1"
#   local -a words
#   local word
#   local found_target=0
#
#   if has_shell_control_syntax "$command"; then
#     return 1
#   fi
#
#   shell_words "$command" words || return 1
#
#   case "${words[0]:-}" in
#     touch)
#       ;;
#     *)
#       return 1
#       ;;
#   esac
#
#   for word in "${words[@]:1}"; do
#     case "$word" in
#       --)
#         continue
#         ;;
#       -*)
#         continue
#         ;;
#     esac
#
#     found_target=1
#     if [[ "$word" != /* ]]; then
#       return 1
#     fi
#     if [[ -n "$(repo_root_for_path "$word")" ]]; then
#       return 1
#     fi
#   done
#
#   [[ "$found_target" -eq 1 ]]
# }
#
# is_read_only_rg_command() {
#   local command="$1"
#   local -a words
#   local word
#
#   shell_words "$command" words || return 1
#
#   if [[ "${words[0]:-}" != "rg" ]]; then
#     return 1
#   fi
#
#   for word in "${words[@]:1}"; do
#     case "$word" in
#       --pre|--pre=*)
#         return 1
#         ;;
#     esac
#   done
#
#   return 0
# }
#
# has_shell_control_syntax() {
#   local command="$1"
#
#   if [[ "$command" == *$'\n'* || "$command" == *$'\r'* ]]; then
#     return 0
#   fi
#
#   case "$command" in
#     *[\;\&\|\<\>\`\(\)\$]*)
#       return 0
#       ;;
#     *)
#       return 1
#       ;;
#   esac
# }
#
# has_shell_path_indirection() {
#   local command="$1"
#   local assignment_regex='(^|[[:space:];])[_a-zA-Z][_a-zA-Z0-9]*=[^[:space:];]*/'
#
#   if [[ "$command" =~ $assignment_regex ]]; then
#     return 0
#   fi
#
#   case "$command" in
#     *'$'*'/'*|*'${'*'}'*'/'*)
#       return 0
#       ;;
#     *)
#       return 1
#       ;;
#   esac
# }
#
# git_command_cwd() {
#   local command="$1"
#   local selected_dir="${2:-$cwd}"
#   local -a words
#   local i
#   local option_path
#
#   shell_words "$command" words || return 1
#
#   if [[ "${words[0]:-}" != "git" ]]; then
#     return 1
#   fi
#
#   selected_dir="$(canonical_path "$selected_dir")"
#   i=1
#   while (( i < ${#words[@]} )); do
#     case "${words[i]}" in
#       -C)
#         if [[ -z "${words[i + 1]:-}" ]]; then
#           return 1
#         fi
#         if [[ "${words[i + 1]}" = /* ]]; then
#           selected_dir="$(canonical_path "${words[i + 1]}")"
#         else
#           selected_dir="$(canonical_path "$selected_dir/${words[i + 1]}")"
#         fi
#         ((i += 2))
#         ;;
#       --work-tree)
#         if [[ -z "${words[i + 1]:-}" ]]; then
#           return 1
#         fi
#         selected_dir="$(resolve_git_path "${words[i + 1]}" "$selected_dir")"
#         ((i += 2))
#         ;;
#       --work-tree=*)
#         option_path="${words[i]#--work-tree=}"
#         if [[ -z "$option_path" ]]; then
#           return 1
#         fi
#         selected_dir="$(resolve_git_path "$option_path" "$selected_dir")"
#         ((i++))
#         ;;
#       --git-dir|--namespace|-c)
#         ((i += 2))
#         ;;
#       --git-dir=*|--namespace=*|-c*)
#         ((i++))
#         ;;
#       --no-pager|--paginate|--no-optional-locks|--literal-pathspecs|--no-replace-objects)
#         ((i++))
#         ;;
#       *)
#         printf '%s\n' "$selected_dir"
#         return 0
#         ;;
#     esac
#   done
#
#   printf '%s\n' "$selected_dir"
# }
#
# git_command_has_mismatched_git_dir() {
#   local command="$1"
#   local selected_dir="${2:-$cwd}"
#   local -a words
#   local i
#   local option_path
#   local explicit_git_dir=""
#   local selected_git_dir
#   local invalid_selected_dir=0
#
#   shell_words "$command" words || return 1
#
#   if [[ "${words[0]:-}" != "git" ]]; then
#     return 1
#   fi
#
#   selected_dir="$(canonical_path "$selected_dir")"
#   i=1
#   while (( i < ${#words[@]} )); do
#     case "${words[i]}" in
#       -C)
#         if [[ -z "${words[i + 1]:-}" ]]; then
#           return 1
#         fi
#         selected_dir="$(resolve_git_path "${words[i + 1]}" "$selected_dir")"
#         ((i += 2))
#         ;;
#       --namespace|-c)
#         ((i += 2))
#         ;;
#       --git-dir)
#         option_path="${words[i + 1]:-}"
#         if [[ -z "$option_path" ]]; then
#           return 0
#         fi
#         explicit_git_dir="$(resolve_git_path "$option_path" "$selected_dir")"
#         ((i += 2))
#         ;;
#       --work-tree)
#         option_path="${words[i + 1]:-}"
#         if [[ -z "$option_path" ]]; then
#           invalid_selected_dir=1
#           ((i += 2))
#           continue
#         fi
#         selected_dir="$(resolve_git_path "$option_path" "$selected_dir")"
#         ((i += 2))
#         ;;
#       --git-dir=*)
#         option_path="${words[i]#--git-dir=}"
#         if [[ -z "$option_path" ]]; then
#           return 0
#         fi
#         explicit_git_dir="$(resolve_git_path "$option_path" "$selected_dir")"
#         ((i++))
#         ;;
#       --work-tree=*)
#         option_path="${words[i]#--work-tree=}"
#         if [[ -z "$option_path" ]]; then
#           invalid_selected_dir=1
#           ((i++))
#           continue
#         fi
#         selected_dir="$(resolve_git_path "$option_path" "$selected_dir")"
#         ((i++))
#         ;;
#       --namespace=*|-c*|--no-pager|--paginate|--no-optional-locks|--literal-pathspecs|--no-replace-objects)
#         ((i++))
#         ;;
#       *)
#         break
#         ;;
#     esac
#   done
#
#   if [[ -z "$explicit_git_dir" ]]; then
#     return 1
#   fi
#
#   if [[ "$invalid_selected_dir" -eq 1 ]]; then
#     return 0
#   fi
#
#   selected_git_dir="$(git -C "$selected_dir" rev-parse --absolute-git-dir 2>/dev/null || true)"
#   if [[ -z "$selected_git_dir" ]]; then
#     return 0
#   fi
#
#   selected_git_dir="$(canonical_path "$selected_git_dir")"
#   if [[ "$explicit_git_dir" != "$selected_git_dir" ]]; then
#     return 0
#   fi
#
#   ! is_linked_worktree "$selected_dir"
# }
#
# is_read_only_git_command() {
#   local command="$1"
#   local -a words
#   local -a git_words
#   local word
#   local subcommand
#   local i
#
#   shell_words "$command" words || return 1
#
#   if [[ "${words[0]:-}" != "git" ]]; then
#     return 1
#   fi
#
#   git_words=("git")
#   i=1
#   while (( i < ${#words[@]} )); do
#     case "${words[i]}" in
#       -C|--git-dir|--work-tree|--namespace|-c)
#         ((i += 2))
#         ;;
#       --git-dir=*|--work-tree=*|--namespace=*|-c*)
#         ((i++))
#         ;;
#       --no-pager|--paginate|--no-optional-locks|--literal-pathspecs|--no-replace-objects)
#         ((i++))
#         ;;
#       *)
#         git_words+=("${words[@]:i}")
#         break
#         ;;
#     esac
#   done
#
#   subcommand="${git_words[1]:-}"
#
#   if [[ "$subcommand" == "worktree" && "${git_words[2]:-}" == "add" ]]; then
#     [[ "${git_words[3]:-}" == .worktrees/* ]]
#     return
#   fi
#
#   case "$subcommand" in
#     status|diff|log|show|rev-parse|ls-files)
#       for word in "${git_words[@]:2}"; do
#         case "$word" in
#           --output|--output=*|-o|-o*)
#             return 1
#             ;;
#         esac
#       done
#
#       return 0
#       ;;
#     branch)
#       if (( ${#git_words[@]} == 2 )); then
#         return 0
#       fi
#
#       for word in "${git_words[@]:2}"; do
#         case "$word" in
#           --show-current|--list|--all|--remotes|-a|-r)
#             ;;
#           -d|-D|-f|-m|-M|-c|-C|--delete|--force|--move|--copy|--edit-description|--set-upstream-to|--unset-upstream)
#             return 1
#             ;;
#           *)
#             return 1
#             ;;
#         esac
#       done
#
#       return 0
#       ;;
#     worktree)
#       [[ "${git_words[2]:-}" == "list" ]]
#       ;;
#     *)
#       return 1
#       ;;
#   esac
# }
#
# is_read_only_find_command() {
#   local command="$1"
#   local -a words
#   local word
#
#   shell_words "$command" words || return 1
#
#   if [[ "${words[0]:-}" != "find" ]]; then
#     return 1
#   fi
#
#   for word in "${words[@]}"; do
#     case "$word" in
#       -delete|-exec|-execdir|-ok|-okdir|-fprint|-fprintf|-fls)
#         return 1
#         ;;
#     esac
#   done
#
#   return 0
# }
#
# is_read_only_command() {
#   local command="$1"
#   local -a words
#   local word
#
#   if has_shell_control_syntax "$command"; then
#     return 1
#   fi
#
#   if is_read_only_git_command "$command" || is_read_only_find_command "$command" || is_read_only_rg_command "$command"; then
#     return 0
#   fi
#
#   shell_words "$command" words || return 1
#
#   case "${words[0]:-}" in
#     ""|pwd|ls|grep|cat|head|tail|stat)
#       return 0
#       ;;
#     sed)
#       if [[ "${words[1]:-}" != "-n" ]]; then
#         return 1
#       fi
#
#       for word in "${words[@]:2}"; do
#         case "$word" in
#           -i|--in-place|--in-place=*|-i*)
#             return 1
#             ;;
#         esac
#       done
#
#       return 0
#       ;;
#     wc)
#       [[ "${words[1]:-}" == "-l" ]]
#       ;;
#     *)
#       return 1
#       ;;
#   esac
# }
#
# is_outside_repo_shell_command_allowed() {
#   local command="$1"
#   local base_dir="${2:-$cwd}"
#
#   if command_referenced_main_worktree_root "$command" "$base_dir" >/dev/null; then
#     is_read_only_command "$command"
#     return
#   fi
#
#   return 0
# }
#
# is_shell_tool() {
#   case "$tool_name" in
#     Bash|Shell|shell|shell_command|local_shell|exec_command|functions.exec_command)
#       return 0
#       ;;
#     *)
#       return 1
#       ;;
#   esac
# }
#
# is_direct_write_tool() {
#   case "$tool_name" in
#     apply_patch|Edit|Write|MultiEdit|NotebookEdit|functions.apply_patch)
#       return 0
#       ;;
#     *)
#       return 1
#       ;;
#   esac
# }
#
# is_mcp_tool() {
#   case "$tool_name" in
#     mcp__*)
#       return 0
#       ;;
#     *)
#       return 1
#       ;;
#   esac
# }
#
# has_mcp_command_like_input() {
#   is_mcp_tool || return 1
#
#   jq -e '
#     .tool_input
#     | type == "object"
#     and (
#       has("command") or
#       has("cmd") or
#       has("code") or
#       has("script") or
#       has("shell")
#     )
#   ' <<<"$input" >/dev/null 2>&1
# }
#
# is_mcp_executor_tool() {
#   is_mcp_tool || return 1
#
#   case "$tool_name" in
#     *ctx_execute|*ctx_execute_file|*execute|*exec|*run|*shell|*command*)
#       return 0
#       ;;
#     *)
#       has_mcp_command_like_input
#       ;;
#   esac
# }
#
# is_mcp_write_tool() {
#   case "$tool_name" in
#     *write*|*edit*|*create*|*delete*|*apply_patch*|*move*|*rename*)
#       return 0
#       ;;
#     *)
#       return 1
#       ;;
#   esac
# }
#
# block_reason() {
#   local root="$1"
#
#   cat <<MSG
# Codex worktree guard blocked this write because the current directory is the repository's main worktree.
#
# Create a linked worktree and continue there:
#   git worktree add .worktrees/<slug> -b <branch>
#   cd .worktrees/<slug>
#
# All repo changes and generated artifacts, including docs/superpowers/specs/, docs/superpowers/plans/, docs/solutions/, code, and config files, belong in the feature worktree.
#
# Repository root: $root
# MSG
# }
#
# repo_root="$(repo_root_for)"
# if is_shell_tool; then
#   command="$(command_text)"
#   shell_cwd="$(effective_cwd)"
#   if has_unresolved_git_c_option "$command"; then
#     deny "$(block_reason "$(repo_root_for "$shell_cwd")")"
#   fi
#   if ! is_read_only_git_command "$command"; then
#     if git_command_has_mismatched_git_dir "$command" "$shell_cwd"; then
#       deny "$(block_reason "$(command_referenced_main_worktree_root "$command" "$shell_cwd" || primary_worktree_root_for_current_repo "$shell_cwd" || repo_root_for "$shell_cwd" || printf '%s' "$shell_cwd")")"
#     fi
#   fi
#   command_cwd="$shell_cwd"
#   if git_selected_cwd="$(git_command_cwd "$command" "$shell_cwd")"; then
#     command_cwd="$git_selected_cwd"
#   fi
#
#   if referenced_root="$(command_referenced_main_worktree_root "$command" "$command_cwd")"; then
#     if is_read_only_command "$command"; then
#       exit 0
#     fi
#
#     deny "$(block_reason "$referenced_root")"
#   fi
#
#   repo_root="$(repo_root_for "$command_cwd")"
#   if [[ -z "$repo_root" ]]; then
#     if is_outside_repo_shell_command_allowed "$command" "$command_cwd"; then
#       exit 0
#     fi
#
#     deny "$(block_reason "$(command_referenced_main_worktree_root "$command" "$command_cwd")")"
#   fi
#
#   if is_read_only_command "$command"; then
#     exit 0
#   fi
#   repo_root="$(canonical_path "$repo_root")"
#
#   if is_linked_worktree "$command_cwd"; then
#     if has_shell_control_syntax "$command" && has_shell_path_indirection "$command"; then
#       deny "$(block_reason "$(primary_worktree_root_for_current_repo "$command_cwd")")"
#     fi
#
#     exit 0
#   fi
#
#   if command_targets_outside_git_repo "$command"; then
#     exit 0
#   fi
#
#   deny "$(block_reason "$repo_root")"
# fi
#
# if is_mcp_executor_tool; then
#   found_command=0
#   all_commands_read_only=1
#
#   while IFS= read -r command; do
#     found_command=1
#     if referenced_root="$(command_referenced_main_worktree_root "$command")"; then
#       if ! is_read_only_command "$command"; then
#         deny "$(block_reason "$referenced_root")"
#       fi
#     fi
#
#     if ! is_read_only_command "$command"; then
#       all_commands_read_only=0
#       if [[ -n "$repo_root" ]] && is_linked_worktree && has_shell_control_syntax "$command" && has_shell_path_indirection "$command"; then
#         deny "$(block_reason "$(primary_worktree_root_for_current_repo)")"
#       fi
#     fi
#   done < <(mcp_executor_command_texts)
#
#   if [[ "$found_command" -eq 1 && "$all_commands_read_only" -eq 1 ]]; then
#     exit 0
#   fi
#
#   if [[ -z "$repo_root" ]]; then
#     exit 0
#   fi
#
#   repo_root="$(canonical_path "$repo_root")"
#
#   if is_linked_worktree; then
#     exit 0
#   fi
#
#   deny "$(block_reason "$repo_root")"
# fi
#
# if is_direct_write_tool || is_mcp_write_tool; then
#   found_target=0
#   while IFS= read -r target; do
#     found_target=1
#     if target_repo_root="$(main_worktree_root_for_target "$target")"; then
#       deny "$(block_reason "$target_repo_root")"
#     fi
#   done < <(tool_target_paths)
#
#   if [[ "$found_target" -eq 1 ]]; then
#     exit 0
#   fi
#
#   if [[ -z "$repo_root" ]]; then
#     exit 0
#   fi
#   repo_root="$(canonical_path "$repo_root")"
#
#   if is_linked_worktree; then
#     exit 0
#   fi
#
#   deny "$(block_reason "$repo_root")"
# fi
#
# exit 0
