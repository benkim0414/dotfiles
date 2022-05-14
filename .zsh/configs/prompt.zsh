# If set, parameter expansion, command substitution and arithmetic expansion
# are performed in prompts. Substitutions within prompts do not affect the
# command status.
setopt PROMPT_SUBST
. ~/.zsh/prompt/git-prompt.sh
GIT_PS1_SHOWDIRTYSTATE=true
GIT_PS1_SHOWCOLORHINTS=true
PROMPT="%n@%m:%~\$(__git_ps1 '(%s)')%# "

