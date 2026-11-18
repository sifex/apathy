# Sets REPLY to the model in "$@" most likely to answer fastest, judged by name
# alone, or to nothing. Small tiers (nano, mini, haiku, flash) beat large ones
# (opus, pro, reasoning), newer versions beat older ones, and local models and
# paid speed tiers that are often not enabled are skipped.
apathy-guess-model() {
  emulate -L zsh
  setopt extendedglob
  local id name version
  local -a keys
  integer score
  for id; do
    name=${(L)id#*/}
    case ${(L)id} in
      (lmstudio|ollama|llamacpp|llama.cpp|local)/*) continue ;;
    esac
    [[ $name == (auto|*-(fast|ultrafast|flex|batch|priority)|*(embed|tts|whisper|image|audio|realtime|moderation|cyber)*) ]] && continue
    score=0
    [[ $name == *(nano|lite)* ]] && (( score += 30 ))
    [[ $name == *(haiku|mini|flash|small|instant)* ]] && (( score += 20 ))
    [[ $name == *(opus|pro|ultra|large|max|thinking|reason|deep|high)* || $name == o[0-9]* ]] && (( score -= 20 ))
    [[ $name == *(preview|exp|beta)* ]] && (( score -= 5 ))
    version=0
    [[ $name =~ '[0-9]+([.-][0-9]+)*' ]] && version=${MATCH//-/.}
    keys+=("$(( score + 500 )) $version $id")
  done
  REPLY=${${${(On)keys}[1]}##* }
}
