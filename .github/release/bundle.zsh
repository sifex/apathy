#!/usr/bin/env zsh -f
# Prints apathy.zsh: apathy.plugin.zsh with lib/ inlined and lib/personas/
# embedded, so it can be installed by downloading one file.
emulate -R zsh
cd ${0:A:h:h:h}
local line f
print -r -- '# apathy.zsh: built from https://github.com/sifex/apathy by `make bundle`. Do not edit.'
for line in "${(@f)$(<apathy.plugin.zsh)}"; do
  case $line in
    ('source $_apathy_dir/lib/'*.zsh) print -r -- "$(<${line#source \$_apathy_dir/})" ;;
    ('typeset -gA _apathy_personas')
      print -rn -- 'typeset -gA _apathy_personas=('
      for f in lib/personas/*.md; do print -rn -- " ${f:t:r} ${(qq)$(<$f)}"; done
      print -r -- ' )' ;;
    ('typeset -g _apathy_bundle=') print -r -- 'typeset -g _apathy_bundle=${${(%):-%x}:A}' ;;
    (*) print -r -- $line ;;
  esac
done
