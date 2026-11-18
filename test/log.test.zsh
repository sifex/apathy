#!/usr/bin/env zsh -f
# Where the terminal can't be read: the command log and opt-in stderr capture,
# driven through a real interactive zsh.
emulate -R zsh
zmodload zsh/zpty

root=${0:A:h:h}
source ${0:A:h}/helpers.zsh
sandbox=$(mktemp -d)
trap '/bin/rm -rf $sandbox' EXIT
mkdir "$sandbox/a dir"
fake-agents $sandbox

typeset -i pass=0 fail=0
# run <rc lines> <keys...>: each key string is sent followed by Enter; REPLY is
# the message the last prompt sent to the agent.
run() {
  local rc=$1 line
  out=
  shift
  cat > $sandbox/.zshrc <<EOF
unset TMUX TMUX_PANE
$(fake-rc $sandbox)
PS1='%% ' $rc
$(load-apathy)
EOF
  /bin/rm -f $sandbox/msg
  ready-reset $sandbox
  zpty apathy "ZDOTDIR=${(q)sandbox} TERM=dumb zsh -i"
  for line in "$@" 'print -r -- END'; do zpty-type $sandbox $line; done
  local deadline=$(( EPOCHSECONDS + 20 ))
  while [[ $out != *$'\n'END* ]] && (( EPOCHSECONDS < deadline )); do
    zpty -r -t apathy line 2>/dev/null && out+=$line
  done
  zpty -d apathy
  [[ $out == *$'\n'END* ]] || print -r -- "TIMEOUT: ${(qqq)@}"$'\n'"${out//$'\r'}"
  REPLY=$(cat $sandbox/msg 2>/dev/null)
}
check() {
  local got=${REPLY//[0-9].[0-9]s/N.Ns}
  [[ $got == "$1" ]] && (( ++pass )) || { (( ++fail )); print -r -- "FAIL: $2"$'\n'"want: $1"$'\n'"got:  $got" }
}
hdr=$'Commands I ran since my last message (this terminal\'s output can\'t be read):\n```\n'
errhdr=$'Commands I ran since my last message (this terminal\'s output can\'t be read; each is followed by its stderr):\n```\n'
why=$'\n```\n\nwhy?'
# The shells' HOME is in the sandbox, so this directory is shown in full.
here=$PWD

run '' "cd ${(q)sandbox}/a\ dir" 'false' 'cd /' 'why?'
check "$hdr\$ cd ${(q)sandbox}/a\ dir  # exit 0, N.Ns, $here
\$ false  # exit 1, N.Ns, $sandbox/a dir
\$ cd /  # exit 0, N.Ns, $sandbox/a dir$why" 'exit code, duration and the directory each command started in'

run '' 'true' 'first' 'print hi' 'second'
check "$hdr\$ print hi  # exit 0, N.Ns, $here"$'\n```\n\nsecond' 'log restarts after each prompt'

run '' 'first' 'again'
check 'again' 'no commands, no context'

run 'APATHY_CAPTURE_STDERR=1' 'print -u2 boom; false' 'print -u2 two; print out' 'why?'
check "$errhdr\$ print -u2 boom; false  # exit 1, N.Ns, $here
boom
\$ print -u2 two; print out  # exit 0, N.Ns, $here
two$why" 'stderr captured per command, stdout left out'

run 'APATHY_CAPTURE_STDERR=1' '(sleep 0.4; print -u2 late) &' 'print -u2 now' 'sleep 0.8' 'print -u2 third' 'why?'
check "$errhdr\$ (sleep 0.4; print -u2 late) &  # exit 0, N.Ns, $here
\$ print -u2 now  # exit 0, N.Ns, $here
now
\$ sleep 0.8  # exit 0, N.Ns, $here
\$ print -u2 third  # exit 0, N.Ns, $here
third$why" 'late background stderr is not credited to a later command'

# Personas go in front of everything else, for every agent.
persona=$'Reply as this persona:\n\n'$(<$root/lib/personas/apathy.md)$'\n\n---\n\n'
run 'unset APATHY_PERSONA' 'true' 'why?'
check "$persona$hdr\$ true  # exit 0, N.Ns, $here$why" 'the bundled persona is on by default, then context, then the prompt'

print -r -- 'Talk like a pirate.' > $sandbox/pirate.md
run "APATHY_PERSONA=${(q)sandbox}/pirate.md" 'hello'
check $'Reply as this persona:\n\nTalk like a pirate.\n\n---\n\nhello' 'persona from a file'

run 'APATHY_PERSONA=nope' 'hello'
check '' 'an unknown persona sends nothing'
[[ $out == *"apathy: no persona 'nope' (a file, or one of: apathy)"* ]] && (( ++pass )) || { (( ++fail )); print -r -- "FAIL: unknown persona error: ${out//$'\r'}" }

print "log ($APATHY_TEST_AGENT, ${APATHY_TEST_PLUGIN:t}): $pass passed, $fail failed"
(( fail == 0 ))
