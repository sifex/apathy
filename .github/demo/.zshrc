# A clean shell for recording apathy: only the prompt character, no personal
# history. Start it with `make demo`.

path=($HOME/.apathy/bin $HOME/.bun/bin $HOME/.local/bin /opt/homebrew/bin $path)
unset HISTFILE
HISTSIZE=1000
setopt hist_ignore_space interactive_comments

# Your p10k look, minus every segment except the prompt character.
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
source ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(prompt_char)
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=()
typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
p10k reload

source ${${(%):-%x}:A:h:h:h}/apathy.plugin.zsh

# An empty stage, so no real files end up on camera.
rm -rf /tmp/apathy-demo.*(N)
cd $(mktemp -d /tmp/apathy-demo.XXXXXX)
clear
