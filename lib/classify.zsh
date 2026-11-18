zmodload zsh/parameter

typeset -ga _apathy_precommands=(time nocorrect noglob command builtin exec)
# Reserved words that start English sentences as often as shell constructs.
typeset -ga _apathy_control_words=(if elif else then fi for foreach while until select case esac do done end function repeat)
# Commands that start replies more often than command lines ("yes please",
# "read the README", "test it"), and hang or do nothing when run by mistake.
typeset -ga _apathy_reply_words=(yes read test)
(( ${+APATHY_PROMPT_WORDS} )) || typeset -ga APATHY_PROMPT_WORDS=(what write)

# Sets REPLY to "empty", "command" or "prompt". No forks, no subshells.
apathy-classify() {
  local autocd=$options[autocd]
  emulate -L zsh
  setopt extendedglob

  local buf=${1##[[:space:]]#}
  REPLY=empty
  [[ -n $buf ]] || return 0
  REPLY=command

  local -a words=(${(z)buf})
  local w name
  local -i i=1
  while (( i <= $#words )); do
    w=$words[i]
    name=${(Q)w}
    if [[ $w == [[:alpha:]_][[:IDENT:]]#(\[*\]|)(+|)=* ]] ||
       (( ${_apathy_precommands[(Ie)$name]} && i < $#words )); then
      (( i++ ))
      continue
    fi
    break
  done
  (( i > $#words )) && return 0

  # Redirections and shell syntax: > >> < 2>&1 ( { [[ ! $ ~ / . \ # ^ - ...
  [[ $w == [0-9]#[\<\>]* ]] && return 0
  [[ $w == [[:alnum:]_@\"\']* ]] || return 0

  (( ${APATHY_PROMPT_WORDS[(Ie)$name]} )) && { REPLY=prompt; return 0 }

  [[ -d $name && $autocd == on ]] && return 0
  if [[ $name == */* ]]; then
    [[ -f $name && -x $name ]] && return 0
  elif (( ${_apathy_control_words[(Ie)$name]} )); then
    # "for f in *; do" is shell; "if I rename this, what breaks?" is a prompt.
    [[ $buf == *[\;\&\|\(\)\{\}\<\>\$\`]* ]] && return 0
  elif (( ${_apathy_reply_words[(Ie)$name]} )); then
    # "yes | head", "read -r x" and "test -f x" are shell.
    [[ $buf == *[\;\&\|\(\)\{\}\<\>\$\`]* || $buf == *[[:space:]]-* ]] && return 0
  elif (( ${reswords[(Ie)$name]} || $+aliases[$name] || $+galiases[$name] ||
          $+functions[$name] || $+builtins[$name] || $+commands[$name] )); then
    return 0
  elif [[ $name == ?*.?* ]] && (( $+saliases[${name##*.}] )); then
    return 0
  fi
  REPLY=prompt
}
