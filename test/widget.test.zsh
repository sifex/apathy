#!/usr/bin/env zsh -f
# End-to-end: drive a real interactive zsh through zpty and press Enter.
emulate -R zsh
zmodload zsh/zpty zsh/datetime

root=${0:A:h:h}
source ${0:A:h}/helpers.zsh
sandbox=$(mktemp -d)
trap '/bin/rm -rf $sandbox' EXIT
fake-agents $sandbox

cat > $sandbox/.zshrc <<EOF
unset TMUX TMUX_PANE
$(fake-rc $sandbox)
PS1='%% ' PS2='> ' HISTSIZE=100
setopt histignorespace no_prompt_sp no_prompt_cr
# Atuin's history hook, by name, loaded before apathy.
_atuin_preexec() { print -r -- "\$1" >> ${(q)sandbox}/atuin }
autoload -Uz add-zsh-hook
add-zsh-hook preexec _atuin_preexec
prior-accept() { zle .accept-line }
zle -N accept-line prior-accept
source ${(q)APATHY_TEST_PLUGIN}
$(load-apathy)
EOF

typeset -i pass=0 fail=0
locale=
# run <expected output lines> <keys...>: each key string is sent followed by
# Enter (^M). A ^J inside one is Shift+Enter.
run() {
  local want=$1 out line
  shift
  zpty -d apathy 2>/dev/null
  ready-reset $sandbox
  zpty apathy "$locale ZDOTDIR=${(q)sandbox} TERM=dumb zsh -i"
  out=
  for line in "$@" 'print -r -- END'; do zpty-type $sandbox $line; done
  local deadline=$(( EPOCHSECONDS + 20 ))
  while [[ $out != *$'\n'END$'\r'* ]] && (( EPOCHSECONDS < deadline )); do
    zpty -r -t apathy line 2>/dev/null && out+=$line
  done
  zpty -d apathy
  if [[ ${out//$'\r'} == *$'\n'$want$'\n'* ]]; then
    (( ++pass ))
  else
    (( ++fail ))
    print -r -- "FAIL: ${(qqq)@}: want ${(qqq)want}"
    print -r -- ${out//$'\r'}
  fi
}

run "OUT:explain this error" 'explain this error'
run "OUT:what's up | cat >> x" "what's up | cat >> x"
run 'OUT:why $HOME `x` $(y) "z"' 'why $HOME `x` $(y) "z"'
run "H:explain this" 'explain this' 'print -r -- "H:$(fc -ln -1)"'
run "H:print -r -- \$PWD" 'print -r -- $PWD' ' secret prompt' 'print -r -- "H:$(fc -ln -1)"'
# The second prompt in a shell continues the first one's session.
/bin/rm -f $sandbox/argv $sandbox/home/.claude/projects/*/*(N) $sandbox/home/.codex/sessions/*/*/*/*(N)
run "OUT:and again" 'explain this' 'and again'
calls=("${(@f)$(<$sandbox/argv)}")
case $APATHY_TEST_AGENT in
  (opencode) one=${${calls[1]##*--session | }%% | *} two=${${calls[2]##*--session | }%% | *} ;;
  (claude) one=${${calls[1]##*--session-id | }%% | *} two=${${calls[2]##*--resume | }%% | *} ;;
  (codex) one=$([[ $calls[1] != *resume* ]] && print 0199a213-81c0-7800-8aa1-bbab2a035a53) two=${${calls[2]##*resume | }%% | *} ;;
esac
if (( $#calls == 2 )) && [[ -n $one && $one == $two && $calls[2] == *" | and again" ]]; then
  (( ++pass ))
else
  (( ++fail )); print -r -- "FAIL: session continuity"$'\n'"${(F)calls}"
fi
run "S:0" 'false' 'explain this' 'print -r -- "S:$?"'
run "S:7" 'please fail' 'print -r -- "S:$?"'
run "H2:false|explain this|" 'false' 'explain this' 'print -r -- "H2:$(fc -ln -2 | tr "\n" "|")"'
# Without a UTF-8 locale the prompt line is aborted instead, so $? is 1.
locale='LC_ALL=C LANG=C'
run "OUT:what's up | cat >> x" "what's up | cat >> x"
run "S:1" 'explain this' 'print -r -- "S:$?"'
run "H2:false|explain this|" 'false' 'explain this' 'print -r -- "H2:$(fc -ln -2 | tr "\n" "|")"'
locale=
run "hello" 'print -r -- hello'
run "a b | c" 'print -r -- "a b | c"'
run "b c" 'print -r -- "prompt?' 'b c"'
run "1" 'for i in 1; do' 'print -r -- $i' 'done'
# Atuin records the prompt, not the line apathy runs in its place.
/bin/rm -f $sandbox/atuin
run "hi" 'explain this' 'print -r -- hi'
REPLY=$(<$sandbox/atuin)
[[ $REPLY == $'explain this\nprint -r -- hi\nprint -r -- END' ]] && (( ++pass )) || { (( ++fail )); print -r -- "FAIL: Atuin got ${(qqq)REPLY}" }
# Shift+Enter adds a line to a prompt, and runs a command as Enter does.
run $'OUT:explain this:\nsecond line' $'explain this:\nsecond line'
run $'OUT:first\nsecond\nthird' $'first\nsecond\nthird'
run "hello" $'print -r -- hello\n'
# So does a trailing backslash, unless it's escaped.
run $'OUT:tell me \nmore' $'tell me \\\rmore'
run 'OUT:what is \\' 'what is \\'
run "H:explain this:\\nsecond line" $'explain this:\nsecond line' 'print -r -- "H:$(fc -ln -1)"'

print "widget ($APATHY_TEST_AGENT, ${APATHY_TEST_PLUGIN:t}): $pass passed, $fail failed"
(( fail == 0 ))
