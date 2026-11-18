typeset -g APATHY_VERSION=0.1.0 # x-release-please-version
typeset -g _apathy_dir=${${(%):-%x}:A:h}
source $_apathy_dir/lib/classify.zsh
source $_apathy_dir/lib/models.zsh
# `make bundle` embeds lib/personas/ here and records apathy.zsh's own path,
# for installs that download that one file.
typeset -gA _apathy_personas
typeset -g _apathy_bundle=
zmodload zsh/datetime zsh/system

# Prefer the native OpenCode client (~40ms faster to start than the TypeScript one).
_apathy_opencode=$HOME/.apathy/bin/opencode-native
[[ -x $_apathy_opencode ]] || _apathy_opencode=${commands[opencode-native]:-${commands[opencode]}}
if (( ! ${+APATHY_AGENT} )); then
  if [[ -n $_apathy_opencode ]]; then APATHY_AGENT=opencode
  elif (( $+commands[claude] )); then APATHY_AGENT=claude
  else APATHY_AGENT=codex
  fi
fi
: ${APATHY_OPENCODE:="${_apathy_opencode:-opencode} run --auto"}
: ${APATHY_CLAUDE:="claude -p --permission-mode auto"}
: ${APATHY_CODEX:="codex exec --approve-for-me --skip-git-repo-check"}
# Defaults when APATHY_MODEL is unset: OpenCode's is guessed from your models on
# the first prompt, Claude's is its fastest tier, Codex keeps its own default.
# APATHY_MODEL='' passes no model.
typeset -gA _apathy_models=(claude haiku codex '')
: ${APATHY_CONTEXT_LINES:=100}
# The bundled persona unless set; APATHY_PERSONA='' turns it off.
: ${APATHY_PERSONA=apathy}

# The terminal whose scrollback can be read, if any. tmux first: inside tmux,
# the outer terminal sees the whole tmux screen.
if [[ -n $TMUX_PANE ]]; then _apathy_term=tmux
elif [[ $TERM_PROGRAM == iTerm.app && -n $ITERM_SESSION_ID ]]; then _apathy_term=iterm
elif [[ $TERM_PROGRAM == Apple_Terminal ]]; then _apathy_term=terminal
elif [[ -n $WEZTERM_PANE ]]; then _apathy_term=wezterm
elif [[ -n $KITTY_WINDOW_ID ]]; then _apathy_term=kitty
else _apathy_term=
fi

# One agent session per terminal pane, derived from the pane so nothing is stored.
# iTerm2 and Terminal.app put a UUID in $TERM_SESSION_ID.
_apathy_uuid=${(L)TERM_SESSION_ID#*:}
case $_apathy_term in
  tmux) printf -v _apathy_uuid '%08x-0000-4000-8000-%012x' ${${TMUX#*,}%%,*} ${TMUX_PANE#%} ;;
  iterm) _apathy_uuid=${(L)ITERM_SESSION_ID#*:} ;;
  wezterm) printf -v _apathy_uuid '%08x-0000-4000-8002-%012x' ${${WEZTERM_UNIX_SOCKET##*[^0-9]}:-0} $WEZTERM_PANE ;;
  kitty) printf -v _apathy_uuid '%08x-0000-4000-8003-%012x' ${KITTY_PID:-0} $KITTY_WINDOW_ID ;;
esac
[[ ${#_apathy_uuid} == 36 && $_apathy_uuid != *[^0-9a-f-]* ]] ||
  printf -v _apathy_uuid '%08x-0000-4000-8001-%012x' $$ 0

# Memory only: the pending prompt; the previous prompt and the scrollback row
# it was echoed on, which bound the next context because the session already
# has what came before it; Codex's thread ID, which Codex chooses itself; and
# the commands run since the last prompt.
typeset -g _apathy_pending= _apathy_last= _apathy_last_echo= _apathy_codex_thread= _apathy_cmd= _apathy_cmd_start= _apathy_cmd_dir=
typeset -gi _apathy_last_row=0
typeset -ga _apathy_log=()

# Opt-in stderr capture where the terminal can't be read: a FIFO deleted as soon
# as it's open, so the captured text only ever lives in a pipe buffer.
typeset -g _apathy_err_pipe= _apathy_err_w= _apathy_err_tty=
typeset -gi _apathy_err_seq=0
if [[ -n $APATHY_CAPTURE_STDERR && -z $_apathy_term ]]; then
  () {
    local fifo=${TMPDIR:-/tmp}/apathy-$$-$RANDOM
    mkfifo -m 600 $fifo && exec {_apathy_err_pipe}<>$fifo
    rm -f $fifo
  }
fi

# Renders `opencode run --format json` without its "> build · model" header,
# which the plain output always prints. Paths in tool calls are shown relative
# to the current directory. Lines that aren't JSON pass through.
_apathy-render() {
  jq --unbuffered -Rrj --arg cwd ${${PWD:A}#/private} '
    def dim: "\u001b[90m" + . + "\u001b[0m\n";
    def rel: ltrimstr("/private") | if startswith($cwd + "/") then .[($cwd | length) + 1:] else . end;
    (fromjson? // {type: "raw", raw: .}) as $e
    | if $e.type == "text" then $e.part.text + "\n"
      elif $e.type == "tool_use" then $e.part as $p
        | if $p.state.input.command then ("$ " + $p.state.input.command | dim) + ($p.state.output // "" | rtrimstr("\n") | if . == "" then "" else dim end)
          else "→ " + $p.tool + " " + ([$p.state.input[]? | strings][0] // "" | rel) | dim end
      elif $e.type == "error" then "\u001b[91;1mError:\u001b[0m " + ($e.error.message // ($e.error | tostring)) + "\n"
      elif $e.type == "raw" then $e.raw + "\n"
      else empty end'
}

# Sets REPLY to the model to pass, listing OpenCode's models once per shell.
_apathy-model() {
  if (( ${+APATHY_MODEL} )); then
    REPLY=$APATHY_MODEL
    return
  fi
  if [[ $APATHY_AGENT == opencode ]] && (( ! ${+_apathy_models[opencode]} )); then
    apathy-guess-model ${(f)"$(${${=APATHY_OPENCODE}[1]} models 2>/dev/null)"}
    _apathy_models[opencode]=$REPLY
  fi
  REPLY=$_apathy_models[$APATHY_AGENT]
}

_apathy-run() {
  _apathy-model
  local model=$REPLY
  case $APATHY_AGENT in
    opencode)
      local -a args=(${model:+-m} $model --session ses_apathy${_apathy_uuid//-} $1)
      (( $+commands[jq] )) || { ${=APATHY_OPENCODE} $args; return }
      ${=APATHY_OPENCODE} --format json $args | _apathy-render
      return $pipestatus[1] ;;
    claude)
      local -a seen=(${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/$_apathy_uuid.jsonl(N))
      ${=APATHY_CLAUDE} ${model:+--model} $model ${${seen:+--resume}:---session-id} $_apathy_uuid $1 ;;
    codex)
      if [[ -n $_apathy_codex_thread ]]; then
        ${=APATHY_CODEX} ${model:+-m} $model resume $_apathy_codex_thread $1
        return
      fi
      ${=APATHY_CODEX} ${model:+-m} $model $1
      local exit=$?
      local -a newest=(${CODEX_HOME:-$HOME/.codex}/sessions/*/*/*/rollout-*.jsonl(N.om[1]))
      (( $#newest )) && _apathy_codex_thread=${${newest[1]:t:r}[-36,-1]}
      return exit ;;
    *)
      print -u2 "apathy: unknown APATHY_AGENT '$APATHY_AGENT' (opencode, claude or codex)"
      return 1 ;;
  esac
}

# apathy-model [model]: set this shell's model, or pick one with fzf.
apathy-model() {
  local model=$1
  if (( ! $# )); then
    local -a list
    case $APATHY_AGENT in
      opencode) list=(${(f)"$(${${=APATHY_OPENCODE}[1]} models 2>/dev/null)"}) ;;
      claude) list=(haiku sonnet opus) ;;
    esac
    if (( ! $#list || ! $+commands[fzf] )); then
      _apathy-model
      print -r -- "apathy: $APATHY_AGENT uses ${REPLY:-its default model}"
      return
    fi
    model=$(print -rl -- $list | fzf --height=40% --reverse --prompt="$APATHY_AGENT model> ") || return
  fi
  typeset -g APATHY_MODEL=$model
  print -r -- "apathy: $APATHY_AGENT now uses ${model:-its default model}"
}

# Prints this pane's scrollback, read live from the terminal. The AppleScript
# terminals try the focused tab first in one request: each one is a round trip.
_apathy-screen() {
  case $_apathy_term in
    tmux) tmux capture-pane -p -J -S - -t $TMUX_PANE ;;
    wezterm) wezterm cli get-text --pane-id $WEZTERM_PANE --start-line -100000 ;;
    kitty) kitty @ get-text --match id:$KITTY_WINDOW_ID --extent all ;;
    iterm) osascript - ${ITERM_SESSION_ID#*:} <<'EOF'
on run argv
  tell application "iTerm2"
    try
      set {u, c} to {unique id, contents} of current session of current window
      if u is item 1 of argv then return c
    end try
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is item 1 of argv then return contents of s
        end repeat
      end repeat
    end repeat
  end tell
end run
EOF
      ;;
    terminal) osascript - $TTY <<'EOF'
on run argv
  tell application "Terminal"
    try
      set {y, h} to {tty, history} of selected tab of front window
      if y is item 1 of argv then return h
    end try
    repeat with w in windows
      repeat with t in tabs of w
        if tty of t is item 1 of argv then return history of t
      end repeat
    end repeat
  end tell
end run
EOF
      ;;
  esac
}

# Sets REPLY to the index in $lines of the bottom-most row where $1 starts,
# rejoining soft-wrapped rows, or 0.
_apathy-rfind() {
  local tail= i
  for (( i = $#lines; i > 0; i-- )); do
    tail=$lines[i]$tail
    tail=${tail[1,${#lines[i]}+${#1}]}
    [[ $tail == *"$1"* ]] && { REPLY=$i; return }
  done
  REPLY=0
}

# Sets REPLY to at most $1 lines of this pane's scrollback between the previous
# prompt and the echo of prompt $2.
_apathy-context() {
  setopt localoptions extendedglob
  local text=$(_apathy-screen 2>/dev/null)
  local -a lines=("${(@)${(@f)text}%%[ $'\t']##}")
  local row=$_apathy_last_row echo=$_apathy_last_echo
  _apathy-rfind ${${(f)2}[1]}
  _apathy_last_row=$REPLY _apathy_last_echo=$lines[REPLY]
  (( REPLY )) || { REPLY=; return }
  lines=("${(@)lines[1,REPLY-1]}")
  # The previous prompt's echo, found by its row if the scrollback hasn't
  # moved, else by text, which an answer quoting the prompt can also match.
  if (( row )) && [[ $lines[row] == $echo ]]; then
    lines=("${(@)lines[row,-1]}")
  elif [[ -n $_apathy_last ]]; then
    _apathy-rfind ${${(f)_apathy_last}[1]}
    (( REPLY )) && lines=("${(@)lines[REPLY,-1]}")
  fi
  (( $#lines > $1 )) && shift $(( $#lines - $1 )) lines
  [[ -n $_apathy_go ]] && lines=("${(@)lines//$_apathy_go}")
  REPLY=${${(F)lines}##$'\n'##}
  REPLY=${REPLY%%$'\n'##}
}

# stderr goes to the screen through tee and, via tail, the last 4KB comes back
# as one "seq:text\0" record. The seq drops late writes from background jobs.
_apathy-err-start() {
  (( ++_apathy_err_seq ))
  exec {_apathy_err_tty}>&2
  exec {_apathy_err_w}> >(tee /dev/fd/$_apathy_err_tty | { t=$(tail -c 4096); print -rn -- "$_apathy_err_seq:$t"$'\0' } >&$_apathy_err_pipe) 2>&$_apathy_err_w
}

# Restores stderr and sets REPLY to what the command wrote to it. Waiting for
# the record also means its text reached the screen before the next prompt.
_apathy-err-stop() {
  exec 2>&$_apathy_err_tty {_apathy_err_tty}>&- {_apathy_err_w}>&-
  _apathy_err_w=
  local buf= chunk rec
  REPLY=
  while :; do
    while [[ $buf == *$'\0'* ]]; do
      rec=${buf%%$'\0'*} buf=${buf#*$'\0'}
      [[ $rec == $_apathy_err_seq:* ]] && { REPLY=${rec#*:}; return }
    done
    sysread -t 0.2 -i $_apathy_err_pipe chunk || return
    buf+=$chunk
  done
}

# Prompts never reach the zsh parser. The widget swaps the line for a command
# named with one non-breaking space and shows the prompt as display-only text
# in front of it, so the agent runs as a real command and $? is its exit
# status. (zle draws zero-width characters as <200b>; a trailing space is invisible.)
# Only a UTF-8 locale can encode it. Elsewhere the line is aborted and precmd
# runs the agent, so $? is 1 after a prompt.
if [[ ${(L)${LC_ALL:-${LC_CTYPE:-$LANG}}} == *utf(-|)8* ]]; then
  typeset -g _apathy_go=$'\u00a0'
  functions[$_apathy_go]=_apathy-go
else
  typeset -g _apathy_go=
fi

_apathy-preexec() {
  [[ -n $_apathy_go && $1 == $_apathy_go ]] && return
  _apathy_cmd=$1 _apathy_cmd_start=$EPOCHREALTIME _apathy_cmd_dir=${PWD/#$HOME/\~}
  [[ -n $_apathy_err_pipe ]] && _apathy-err-start
}

# The prompt goes into history instead of the swapped line. Adding it after
# the rejected line also evicts that line from memory.
_apathy-addhistory() {
  [[ -z $_apathy_go || $1 != $_apathy_go$'\n' ]]
}

_apathy-accept-line() {
  setopt localoptions extendedglob
  if [[ $CONTEXT == start ]]; then
    apathy-classify $BUFFER
    if [[ $REPLY == prompt ]]; then
      # ^J (Shift+Enter in terminals set up for coding agents, or Ctrl+J) adds a
      # line to the prompt, and so does a trailing backslash, as in zsh.
      if [[ $KEYS == $'\n' ]]; then
        LBUFFER+=$'\n'
        return
      fi
      if (( ${#${(M)BUFFER%%\\##}} % 2 )); then
        BUFFER=${BUFFER%\\}$'\n'
        CURSOR=$#BUFFER
        return
      fi
      _apathy_pending=$BUFFER
      if [[ -n $_apathy_go ]]; then
        PREDISPLAY=$BUFFER BUFFER=$_apathy_go
        zle .accept-line
      else
        zle send-break
      fi
      return
    fi
  fi
  zle _apathy-orig-accept-line
}

_apathy-precmd() {
  local exit=$? err=
  if [[ -n $_apathy_cmd ]]; then
    [[ -n $_apathy_err_w ]] && { _apathy-err-stop; err=$REPLY }
    printf -v REPLY '$ %s  # exit %d, %.1fs, %s' $_apathy_cmd $exit $(( EPOCHREALTIME - _apathy_cmd_start )) $_apathy_cmd_dir
    _apathy_log+=($REPLY${err:+$'\n'$err})
    (( $#_apathy_log > 50 )) && shift _apathy_log
    _apathy_cmd=
  fi
  # Atuin records each command line from its preexec hook. Give it the prompt
  # instead of the line apathy swaps in. Atuin may load before or after apathy.
  if [[ -n $_apathy_go ]] && (( $+functions[_atuin_preexec] && ! $+functions[_apathy-atuin-preexec] )); then
    functions[_apathy-atuin-preexec]=$functions[_atuin_preexec]
    _atuin_preexec() { _apathy-atuin-preexec "${${1:#$_apathy_go}:-$_apathy_pending}" "${@:2}" }
  fi
  # Set only if the prompt line was aborted (no UTF-8 locale).
  [[ -n $_apathy_pending ]] && _apathy-go
  return 0
}

_apathy-go() {
  [[ -n $_apathy_pending ]] || return 0
  local raw=$_apathy_pending msg=$_apathy_pending
  _apathy_pending=
  [[ -o histignorespace && $raw == [[:space:]]* ]] || print -s -r -- $raw
  if (( APATHY_CONTEXT_LINES > 0 )); then
    if [[ -n $_apathy_term ]]; then
      _apathy-context $APATHY_CONTEXT_LINES $raw
      [[ $REPLY == *[^[:space:]]* ]] &&
        msg=$'Terminal output since my last message, most recent last:\n```\n'$REPLY$'\n```\n\n'$raw
    elif (( $#_apathy_log )); then
      local -a lines=("${(@f)${(F)_apathy_log}}")
      (( $#lines > APATHY_CONTEXT_LINES )) && shift $(( $#lines - APATHY_CONTEXT_LINES )) lines
      msg="Commands I ran since my last message (this terminal's output can't be read${_apathy_err_pipe:+; each is followed by its stderr}):"$'\n```\n'${(F)lines}$'\n```\n\n'$raw
    fi
  fi
  _apathy_log=()
  _apathy_last=$raw
  _apathy-persona || return
  [[ -n $REPLY ]] && msg="Reply as this persona:"$'\n\n'$REPLY$'\n\n---\n\n'$msg
  _apathy-run $msg
}

# Sets REPLY to the instructions named by APATHY_PERSONA: a file, or a persona
# bundled in lib/personas/ (embedded in apathy.zsh). They go in front of every
# message rather than in a system prompt, so switching persona takes effect in
# an existing session.
_apathy-persona() {
  REPLY=
  [[ -n $APATHY_PERSONA ]] || return 0
  local file=$APATHY_PERSONA
  [[ -f $file ]] || file=$_apathy_dir/lib/personas/$file.md
  if [[ -r $file ]]; then
    REPLY=$(<$file)
  elif (( ${+_apathy_personas[$APATHY_PERSONA]} )); then
    REPLY=$_apathy_personas[$APATHY_PERSONA]
  else
    local -a names=(${(ko)_apathy_personas} $_apathy_dir/lib/personas/*.md(N:t:r))
    print -u2 "apathy: no persona '$APATHY_PERSONA' (a file, or one of: ${(j:, :)names})"
    return 1
  fi
}

# Replaces a downloaded apathy.zsh with the latest release, through jsDelivr:
# raw.githubusercontent.com rate-limits more and more. An exact version is
# fetched because jsDelivr caches @latest for up to 12 hours.
apathy-update() {
  emulate -L zsh
  if [[ -z $_apathy_bundle || -f $_apathy_dir/../../apathy.plugin.zsh ]]; then
    print -u2 "apathy: not a downloaded apathy.zsh; update with git pull or your plugin manager"
    return 1
  fi
  local repo=gh/sifex/apathy new=$_apathy_bundle.new old=$APATHY_VERSION
  if [[ ! $(curl -fsSL "https://data.jsdelivr.com/v1/packages/$repo/resolved?specifier=latest") =~ '"version": *"([0-9.]+)"' ]]; then
    print -u2 "apathy: can't look up the latest version"
    return 1
  fi
  local v=$match[1]
  if [[ $v == $old ]]; then
    print "apathy: $old is the latest"
    return
  fi
  if ! curl -fsSL -o $new "https://cdn.jsdelivr.net/$repo@$v/.github/release/apathy.zsh" || ! zsh -n $new 2>/dev/null; then
    rm -f $new
    print -u2 "apathy: download of $v failed"
    return 1
  fi
  mv -f $new $_apathy_bundle && source $_apathy_bundle && print "apathy: $old -> $APATHY_VERSION"
}

if [[ -o zle && $widgets[accept-line] != user:_apathy-accept-line ]]; then
  zle -A accept-line _apathy-orig-accept-line
  zle -N accept-line _apathy-accept-line
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _apathy-preexec
  add-zsh-hook precmd _apathy-precmd
  add-zsh-hook zshaddhistory _apathy-addhistory
fi
