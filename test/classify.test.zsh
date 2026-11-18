#!/usr/bin/env zsh -f
# Table-driven classifier tests in a sandbox: only the fake commands below exist.
emulate -R zsh
setopt extendedglob

root=${0:A:h:h}
sandbox=$(mktemp -d)
trap '/bin/rm -rf $sandbox' EXIT
mkdir -p $sandbox/bin $sandbox/cwd/bin $sandbox/cwd/somedir
for c in ls cat grep git make what write sudo yes; do
  print '#!/bin/sh' > $sandbox/bin/$c
  chmod +x $sandbox/bin/$c
done
cp $sandbox/bin/ls $sandbox/cwd/bin/tool
touch $sandbox/cwd/notes.txt
cd $sandbox/cwd
path=($sandbox/bin)
hash -r

source $root/lib/classify.zsh
alias ll='ls -l'
alias -s md=cat
myfn() { : }

typeset -a cases=(
  # Empty
  empty ''
  empty '   '
  empty $'\t'

  # Plain commands, pipes, redirections, appends
  command 'ls'
  command '   ls -la'
  command 'ls -la | grep foo'
  command 'cat notes.txt | grep x >> out.log'
  command 'cat <<EOF'
  command 'cat notes.txt > copy.txt'
  command 'git commit -m "fix: what'\''s broken"'
  command 'echo "it'\''s fine"'
  command 'echo "multi'
  command 'print hello world'
  command 'sudo rm -rf x'
  command 'ls && cat notes.txt || grep -r foo .'
  command 'ls; explain this'
  command 'make the tests pass'

  # Redirection-led lines
  command '>> notes.txt'
  command '> out'
  command '< notes.txt'
  command '2>&1 ls'
  command '&> log ls'

  # Assignments and precommand modifiers
  command 'FOO=1'
  command 'FOO=1 BAR=2 ls'
  command 'arr[1]=x'
  command 'x+=1 ls'
  command 'time ls'
  command 'time'
  command 'noglob ls *'
  command 'command -v git'
  command 'builtin print hi'
  command 'exec 3>notes.txt'
  command 'nocorrect ls'

  # Quoting and escaping of the command word
  command '"ls" -la'
  command "'ls'"
  command 'l"s" -la'
  command '\ls'

  # Paths and expansions
  command './script.sh'
  command '/bin/ls'
  command '~/bin/x'
  command 'bin/tool --flag'
  command '$EDITOR notes.txt'
  command '`which ls`'
  command '$(echo ls)'
  command '=ls'

  # Shell syntax
  command '(cd /tmp && ls)'
  command '{ ls }'
  command '[[ -f x ]] && ls'
  command '(( x++ ))'
  command '! ls'
  command '# a comment'
  command '!!'
  command '^foo^bar'
  command '- ls'
  command 'if true; then ls; fi'
  command 'for f in *; do'
  command 'while true; do ls; done'
  command 'case $x in'
  command 'function f { ls }'
  command 'repeat 3 { ls }'
  command 'export FOO=1'
  command 'local x'
  command 'typeset -A map'
  command 'coproc cat'
  command 'yes | head -2'
  command 'yes n > answers'
  command 'read -r line'
  command 'read x < file'
  command 'test -f notes.txt && ls'
  command 'test -n "$x"'

  # Aliases, functions, suffix aliases
  command 'll'
  command 'myfn arg'
  command 'README.md'

  # Natural language
  prompt 'explain this error'
  prompt 'what'\''s up'
  prompt 'what is the meaning of this'
  prompt 'write a test for foo'
  prompt 'how do I list files | sorted by size?'
  prompt 'why does cat fail >> sometimes'
  prompt 'fix the bug in "main.go"'
  prompt 'fix it && ship'
  prompt '"make the tests pass"'
  prompt "'git status' explain the output"
  prompt 'git'\''s history is weird'
  prompt 'if I rename this, what breaks?'
  prompt 'if'
  prompt 'for each file explain it'
  prompt 'repeat after me'
  prompt 'case study on caching'
  prompt 'do it again but faster'
  prompt 'yes'
  prompt 'yes please'
  prompt 'yes, do it'
  prompt 'read the README and summarise it'
  prompt 'test it'
  prompt 'test the login flow'
  prompt 'while you'\''re at it, refactor'
  prompt 'time to refactor this'
  prompt 'command to find large files?'
  prompt 'noglob what is this?'
  prompt 'FOO=1 explain this'
  prompt '@src/main.go explain'
  prompt 'src/missing.sh is broken'
  prompt 'notes.txt is out of date'
  prompt '2 plus 2?'
  prompt 'ünïcode prompt'
  prompt 'ls-files are missing'
  prompt 'somedir has stale files'
  prompt $'summarise this\nand that'
)

typeset -i pass=0 fail=0
check() {
  apathy-classify $2
  if [[ $REPLY == $1 ]]; then
    (( ++pass ))
  else
    (( ++fail ))
    print -r -- "FAIL: expected $1, got $REPLY: ${(qqq)2}"
  fi
}

for expected input in "${cases[@]}"; do check $expected $input; done

setopt autocd
check command 'somedir'
check command 'somedir/'
unsetopt autocd

APATHY_PROMPT_WORDS=()
check command 'what is this'
APATHY_PROMPT_WORDS=(make)
check prompt 'make the tests pass'

print "classify: $pass passed, $fail failed"
(( fail == 0 ))
