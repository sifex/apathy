#!/usr/bin/env zsh -f
# Exact argv per agent, using fake opencode/claude/codex binaries in a sandbox.
emulate -R zsh
setopt extendedglob

root=${0:A:h:h}
: ${APATHY_TEST_PLUGIN:=$root/apathy.plugin.zsh}
sandbox=$(mktemp -d)
trap '/bin/rm -rf $sandbox' EXIT
mkdir -p $sandbox/bin $sandbox/home
for c in opencode claude codex; do
  print -r -- '#!/bin/zsh -f
[[ $1 == models ]] && { print -r -- . >> '${(q)sandbox}'/models; print -l acme/big-pro acme/model-mini lmstudio/local-nano; exit }
print -r -- "${0:t} ${(j: | :)@}" >> '${(q)sandbox}'/argv
[[ -n $FAKE_ROLLOUT ]] && mkdir -p ${FAKE_ROLLOUT:h} && touch $FAKE_ROLLOUT' > $sandbox/bin/$c
  chmod +x $sandbox/bin/$c
done

typeset -i pass=0 fail=0
# run <env...> -- <prompt...>: sources the plugin in a clean shell and sends each prompt.
run() {
  local sep=${@[(i)--]}
  /bin/rm -f $sandbox/argv
  /usr/bin/env -i PATH=$sandbox/bin:/usr/bin:/bin HOME=$sandbox/home APATHY_CONTEXT_LINES=0 "${@[1,sep-1]}" \
    zsh -fc 'source $1; shift; for p; do _apathy-run $p; unset FAKE_ROLLOUT; done' _ $APATHY_TEST_PLUGIN "${@[sep+1,-1]}"
  REPLY=$(cat $sandbox/argv 2>/dev/null)
}
check() {
  [[ $REPLY == "$1" ]] && (( ++pass )) || { (( ++fail )); print -r -- "FAIL: $2"$'\n'"want: $1"$'\n'"got:  $REPLY" }
}

# OpenCode's output is rendered from JSON only where jq is installed.
jq=$(PATH=$sandbox/bin:/usr/bin:/bin; (( $+commands[jq] )) && print -rn ' | --format | json')
oc="opencode run | --auto$jq | -m | acme/model-mini"
iterm=(TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t2p0:F2793302-29F4-4352-8843-9C0CC418896A)
uuid=f2793302-29f4-4352-8843-9c0cc418896a
claude="claude -p | --permission-mode | auto | --model | haiku"
codex="codex exec | --approve-for-me | --skip-git-repo-check"

run $iterm -- 'explain this'
check "$oc | --session | ses_apathy${uuid//-} | explain this" 'opencode is the default, with the model guessed from its list'

run $iterm TMUX=/tmp/tmux-501/default,4242,0 TMUX_PANE=%7 -- 'hi'
check "$oc | --session | ses_apathy00001092000040008000000000000007 | hi" 'tmux pane wins over iTerm'

run TERM_PROGRAM=Apple_Terminal TERM_SESSION_ID=0A1B2C3D-0000-4000-8000-00000000ABCD -- 'x'
check "$oc | --session | ses_apathy0a1b2c3d00004000800000000000abcd | x" 'Terminal.app session from TERM_SESSION_ID'

run WEZTERM_PANE=3 WEZTERM_UNIX_SOCKET=/Users/me/.local/share/wezterm/gui-sock-4242 -- 'x'
check "$oc | --session | ses_apathy00001092000040008002000000000003 | x" 'WezTerm session from pane and GUI pid'

run KITTY_WINDOW_ID=5 KITTY_PID=4242 -- 'x'
check "$oc | --session | ses_apathy00001092000040008003000000000005 | x" 'kitty session from window and pid'

screen() {
  REPLY=$(/usr/bin/env -i PATH=$sandbox/bin:/usr/bin:/bin HOME=$sandbox/home "$@" zsh -fc 'source $1; _apathy-screen' _ $APATHY_TEST_PLUGIN)
}
for c in wezterm kitty; do
  print -r -- '#!/bin/zsh -f
print -r -- "${0:t} ${(j: | :)@}"' > $sandbox/bin/$c
  chmod +x $sandbox/bin/$c
done
screen WEZTERM_PANE=3
check 'wezterm cli | get-text | --pane-id | 3 | --start-line | -100000' 'WezTerm scrollback'
screen KITTY_WINDOW_ID=5
check 'kitty @ | get-text | --match | id:5 | --extent | all' 'kitty scrollback'

run $iterm 'APATHY_OPENCODE=opencode run --agent plan' -- 'x'
check "opencode run | --agent | plan$jq | -m | acme/model-mini | --session | ses_apathy${uuid//-} | x" 'per-agent command override'

run $iterm APATHY_MODEL=openai/gpt-6-luna -- 'x'
check "opencode run | --auto$jq | -m | openai/gpt-6-luna | --session | ses_apathy${uuid//-} | x" 'APATHY_MODEL overrides the default'

run $iterm APATHY_MODEL= -- 'x'
check "opencode run | --auto$jq | --session | ses_apathy${uuid//-} | x" 'empty APATHY_MODEL passes no model'

/bin/rm -f $sandbox/models
run $iterm -- 'one' 'two'
REPLY=$(<$sandbox/models)
check . 'models are listed once per shell'

REPLY=$(/usr/bin/env -i PATH=$sandbox/bin:/usr/bin:/bin HOME=$sandbox/home zsh -fc 'source $1; apathy-model' _ $APATHY_TEST_PLUGIN)
check 'apathy: opencode uses acme/model-mini' 'apathy-model shows the guess without fzf'

REPLY=$(/usr/bin/env -i PATH=$sandbox/bin:/usr/bin:/bin HOME=$sandbox/home zsh -fc 'source $1; apathy-model other/m; print -r -- "[$APATHY_MODEL]"; apathy-model ""; print -r -- "[$APATHY_MODEL]"' _ $APATHY_TEST_PLUGIN)
check $'apathy: opencode now uses other/m\n[other/m]\napathy: opencode now uses its default model\n[]' 'apathy-model sets the model for this shell'

run APATHY_AGENT=claude -- 'pid'
[[ $REPLY == "$claude | --session-id | "[0-9a-f](#c8)"-0000-4000-8001-000000000000 | pid" ]] &&
  (( ++pass )) || { (( ++fail )); print -r -- "FAIL: shell pid fallback: $REPLY" }

run $iterm APATHY_AGENT=nope -- 'x' 2>/dev/null
check '' 'unknown agent runs nothing'

mkdir -p $sandbox/home/.apathy/bin
cp $sandbox/bin/opencode $sandbox/home/.apathy/bin/opencode-native
run $iterm -- 'native'
check "opencode-native run | --auto$jq | -m | acme/model-mini | --session | ses_apathy${uuid//-} | native" '~/.apathy/bin/opencode-native wins'

/bin/rm $sandbox/bin/opencode $sandbox/home/.apathy/bin/opencode-native

run $iterm -- 'first' 'second'
check "$claude | --session-id | $uuid | first"$'\n'"$claude | --session-id | $uuid | second" 'claude is next; creates while no transcript exists'

mkdir -p $sandbox/home/.claude/projects/-some-dir
touch $sandbox/home/.claude/projects/-some-dir/$uuid.jsonl
run $iterm -- 'again'
check "$claude | --resume | $uuid | again" 'claude resumes its transcript from any project'

/bin/rm $sandbox/bin/claude
thread=0199a213-81c0-7800-8aa1-bbab2a035a53
old=$sandbox/home/.codex/sessions/2026/01/01/rollout-2026-01-01T00-00-00-00000000-0000-0000-0000-000000000000.jsonl
mkdir -p ${old:h} && touch -t 202601010000 $old
run $iterm FAKE_ROLLOUT=$sandbox/home/.codex/sessions/2026/11/17/rollout-2026-11-17T10-00-00-$thread.jsonl -- 'one' 'two'
check "$codex | one"$'\n'"$codex | resume | $thread | two" 'codex is last; resumes the thread it just created'

run $iterm APATHY_MODEL=gpt-6-sol FAKE_ROLLOUT=$sandbox/home/.codex/sessions/2026/11/17/rollout-2026-11-17T10-00-01-$thread.jsonl -- 'one' 'two'
check "$codex | -m | gpt-6-sol | one"$'\n'"$codex | -m | gpt-6-sol | resume | $thread | two" 'codex model goes before resume'

if (( $+commands[jq] )); then
REPLY=$(print -r -- '{"type":"step_start","part":{}}
{"type":"tool_use","part":{"tool":"shell","state":{"input":{"command":"echo hi"},"output":"hi\n"}}}
{"type":"tool_use","part":{"tool":"read","state":{"input":{"path":"/etc/hosts"}}}}
{"type":"tool_use","part":{"tool":"write","state":{"input":{"filePath":"'$root'/sub/x.md"}}}}
{"type":"text","part":{"text":"Two\nlines"}}
{"type":"error","error":{"message":"Model unavailable: x/y"}}
not json at all' | zsh -fc 'cd $2; source $1; _apathy-render' _ $APATHY_TEST_PLUGIN $root)
check $'\e[90m$ echo hi\e[0m\n\e[90mhi\e[0m\n\e[90m→ read /etc/hosts\e[0m\n\e[90m→ write sub/x.md\e[0m\nTwo\nlines\n\e[91;1mError:\e[0m Model unavailable: x/y\nnot json at all' 'JSON events render without the header'
fi

print "agents (${APATHY_TEST_PLUGIN:t}): $pass passed, $fail failed"
(( fail == 0 ))
