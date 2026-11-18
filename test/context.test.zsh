#!/usr/bin/env zsh -f
# Scrollback context through a real, isolated tmux server.
emulate -R zsh
(( $+commands[tmux] )) || { print 'context: skipped (no tmux)'; exit 0 }

root=${0:A:h:h}
source ${0:A:h}/helpers.zsh
sandbox=$(mktemp -d)
sock=apathy-test-$$
trap 'tmux -L $sock kill-server 2>/dev/null; /bin/rm -rf $sandbox' EXIT

fake-agents $sandbox
cat > $sandbox/.zshrc <<EOF
$(fake-rc $sandbox)
PS1='%% '
APATHY_CONTEXT_LINES=20
$(load-apathy)
EOF

tmux -L $sock -f /dev/null new-session -d -x 120 -y 40 "ZDOTDIR=${(q)sandbox} zsh -i"
typeset -i pass=0 fail=0

send() {
  tmux -L $sock send-keys -l -- $1 \; send-keys Enter
  wait-ready $sandbox
}
wait-ready $sandbox

expect() {
  local want=$1
  shift
  /bin/rm -f $sandbox/msg
  send clear
  tmux -L $sock clear-history
  for line in "$@"; do send $line; done
  if [[ $(<$sandbox/msg 2>/dev/null) == $want ]]; then
    (( ++pass ))
  else
    (( ++fail ))
    print -r -- "FAIL: ${(qqq)@}"$'\n'"want: ${(qqq)want}"$'\n'"got:  ${(qqq)$(<$sandbox/msg 2>/dev/null)}"
  fi
}

h=$'Terminal output since my last message, most recent last:\n```\n'
expect $h$'% seq 3\n1\n2\n3\n```\n\nexplain these' 'seq 3' 'explain these'
# Blank lines inside are kept, at the edges dropped.
expect $h$'% print a; print; print b; print\na\n\nb\n```\n\nexplain gaps' 'print a; print; print b; print' 'explain gaps'
# APATHY_CONTEXT_LINES=20 caps it.
expect $h${(F)${(@f)"$(seq 6 25)"}}$'\n```\n\nexplain those' 'seq 25' 'explain those'
# Output before the previous prompt is already in the session.
# The fake answer quotes the whole message, ending in the prompt itself, so
# only the echo's row tells where the previous prompt was.
answer="OUT:$h% seq 9"$'\n'${(F)${(@f)"$(seq 9)"}}$'\n```\n\nfirst'
expect $h"% first"$'\n'$answer$'\n% seq 2\n1\n2\n```\n\nsecond' 'seq 9' 'first' 'seq 2' 'second'
# A prompt soft-wrapped over two rows is still cut out.
long=${(l:200::y:)}
expect $h$'% print ok\nok\n```\n\n'"why $long" 'print ok' "why $long"
expect "nothing above" 'nothing above'


print "context ($APATHY_TEST_AGENT, ${APATHY_TEST_PLUGIN:t}): $pass passed, $fail failed"
(( fail == 0 ))
