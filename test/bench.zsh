#!/usr/bin/env zsh -f
# Fails if the mean classification takes longer than APATHY_BENCH_MAX_US (default 100µs).
emulate -R zsh
zmodload zsh/datetime

source ${0:A:h:h}/lib/classify.zsh
lines=(
  'ls -la | grep foo >> out.log'
  'explain why "cat file | grep x" fails'
  'FOO=1 BAR=2 time noglob git log --oneline'
  'if I rename this, what breaks?'
  "what's the difference between > and >>?"
  ${(l:2000::x:)}
)
integer n=5000 i
start=$EPOCHREALTIME
for (( i = 0; i < n; i++ )); do
  for l in $lines; do apathy-classify $l; done
done
(( us = (EPOCHREALTIME - start) * 1e6 / (n * $#lines) ))
printf 'bench: %.1fµs per classification\n' $us
(( us < ${APATHY_BENCH_MAX_US:-100} ))
