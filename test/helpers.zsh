# Shared by the end-to-end tests. APATHY_TEST_AGENT (opencode, claude or codex)
# picks which fake agent they run against, through apathy's real default
# command lines, and APATHY_TEST_PLUGIN the build: the source tree's
# apathy.plugin.zsh or the one-file .github/release/apathy.zsh.
: ${APATHY_TEST_AGENT:=opencode}
: ${APATHY_TEST_PLUGIN:=${${(%):-%x}:A:h:h}/apathy.plugin.zsh}

# fake-agents <dir>: fake opencode, claude and codex in <dir>/bin. Each writes
# the prompt (its last argument) to <dir>/msg and its argv to <dir>/argv,
# answers "OUT:<prompt>" (as JSON events for `opencode --format json`), and
# exits 7 if the prompt mentions "fail". Fake Claude and Codex leave session
# files, as the real ones do, so apathy resumes their sessions.
fake-agents() {
  local dir=$1 c
  mkdir -p $dir/bin $dir/home
  for c in opencode claude codex; do
    cat > $dir/bin/$c <<EOF
#!/bin/zsh -f
[[ \$1 == models ]] && { print -l test/large-pro test/small-mini; exit }
msg=\${@[-1]} answer="OUT:\${@[-1]}"
print -r -- \$msg > ${(q)dir}/msg
print -r -- "\${0:t} \${(j: | :)@}" >> ${(q)dir}/argv
if (( \${@[(I)--format]} )); then
  answer=\${answer//\\\\/\\\\\\\\} answer=\${answer//\\"/\\\\\\"} answer=\${answer//\$'\\n'/\\\\n}
  print -r -- '{"type":"text","part":{"text":"'\$answer'"}}'
else
  print -r -- \$answer
fi
if [[ \${0:t} == claude ]] && (( \${@[(I)--session-id]} )); then
  mkdir -p \$HOME/.claude/projects/apathy-test
  touch \$HOME/.claude/projects/apathy-test/\${@[\${@[(I)--session-id]}+1]}.jsonl
fi
if [[ \${0:t} == codex ]]; then
  mkdir -p \$HOME/.codex/sessions/2026/01/01
  touch \$HOME/.codex/sessions/2026/01/01/rollout-2026-01-01T00-00-00-0199a213-81c0-7800-8aa1-bbab2a035a53.jsonl
fi
[[ \$msg == *fail* ]] && exit 7
exit 0
EOF
    chmod +x $dir/bin/$c
  done
}

# fake-rc <dir>: .zshrc lines that point apathy at the fake agents, in a shell
# no real terminal can be detected from, with the persona off so tests see
# exactly the prompt. Each time zle reads a line, it adds a byte to <dir>/ready.
fake-rc() {
  print -r -- "unset ITERM_SESSION_ID TERM_SESSION_ID WEZTERM_PANE KITTY_WINDOW_ID
TERM_PROGRAM=none HOME=${(q)1}/home
path=(${(q)1}/bin \$path)
APATHY_AGENT=$APATHY_TEST_AGENT APATHY_PERSONA=
zle-line-init() { print -n . >> ${(q)1}/ready }
zle -N zle-line-init"
}

# load-apathy: .zshrc lines that source apathy and then, as a user would, the
# plugins in APATHY_TEST_WITH (paths to their .zsh files).
load-apathy() {
  local f
  for f in $APATHY_TEST_PLUGIN ${=APATHY_TEST_WITH}; do print -r -- "source ${(q)f}"; done
}

# ready-reset <dir>: before starting a shell from fake-rc.
# wait-ready <dir> [zpty]: waits up to 10s for zle to read another line in it.
# With zpty, it reads the output of the zpty named apathy into $out meanwhile,
# since a shell whose output isn't read stalls. Keys sent before then are typed ahead: the terminal echoes
# them, and translates them with its own settings rather than zle's, which can
# swap Enter (^M) and Shift+Enter (^J).
typeset -gi _ready_seen=0
ready-reset() {
  /bin/rm -f $1/ready
  _ready_seen=0
}
wait-ready() {
  local i grown line
  for (( i = 0; i < 200; i++ )); do
    grown=($1/ready(NL+$_ready_seen))
    (( $#grown )) && break
    if [[ -n $2 ]] && zpty -r -t apathy line 2>/dev/null; then out+=$line; else sleep 0.05; fi
  done
  (( ++_ready_seen ))
}

# zpty-type <dir> <keys>: types <keys> and Enter (^M) into the zpty named
# apathy once zle is ready for them.
zpty-type() {
  wait-ready $1 zpty
  zpty -wn apathy $2$'\r'
}
