#!/usr/bin/env zsh -f
# apathy-guess-model: which of a provider's models is likely fastest.
emulate -R zsh
source ${0:A:h:h}/lib/models.zsh

typeset -i pass=0 fail=0
# check <expected> <models...>
check() {
  local want=$1
  shift
  apathy-guess-model "$@"
  [[ $REPLY == $want ]] && (( ++pass )) || { (( ++fail )); print -r -- "FAIL: want ${(qqq)want}, got ${(qqq)REPLY} from ${(qqq)@}" }
}

check '' 
check '' lmstudio/qwen3-30b ollama/llama3.2 openai/gpt-5-fast openai/auto
check anthropic/claude-haiku-4-5 anthropic/claude-opus-4-1 anthropic/claude-sonnet-4-5 anthropic/claude-haiku-4-5
check anthropic/claude-sonnet-4-5 anthropic/claude-opus-4-1 anthropic/claude-sonnet-4-5
check openai/gpt-5-nano openai/gpt-5 openai/gpt-5-mini openai/gpt-5-nano openai/o3
check google/gemini-2.5-flash-lite google/gemini-2.5-pro google/gemini-2.5-flash google/gemini-2.5-flash-lite
check google/gemini-2.5-flash google/gemini-3-pro-preview google/gemini-2.5-flash
check openai/gpt-5-mini openai/gpt-5-mini openai/gpt-5-mini-fast openai/gpt-5-mini-flex
check anthropic/claude-haiku-5-5 anthropic/claude-haiku-4-5 anthropic/claude-haiku-5-5
check anthropic/claude-haiku-4-5 anthropic/claude-3-5-haiku-20241022 anthropic/claude-haiku-4-5
check google/gemini-2.5-flash google/gemini-2.5-flash google/gemini-2.5-flash-preview
check openai/gpt-5 openai/gpt-5 openai/text-embedding-3-small openai/gpt-4o-realtime openai/gpt-5.1-cyber
check openrouter/mistral-small openrouter/mistral-large openrouter/mistral-small lmstudio/phi-4-mini
check provider/a-1 provider/a-1

print "models: $pass passed, $fail failed"
(( fail == 0 ))
