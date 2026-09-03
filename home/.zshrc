HISTFILE=$HOME/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt AUTO_CD
setopt EXTENDED_GLOB
setopt CORRECT

bindkey -e

autoload -Uz compinit
compinit

eval "$(dircolors -b)" 2>/dev/null

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

alias ls='LS_COLORS= EZA_COLORS= eza --icons --group-directories-first'
alias ll='LS_COLORS= EZA_COLORS= eza -lh --icons --group-directories-first'
alias la='LS_COLORS= EZA_COLORS= eza -lha --icons --group-directories-first'
alias l='LS_COLORS= EZA_COLORS= eza --icons --group-directories-first'
alias lt='LS_COLORS= EZA_COLORS= eza --tree --icons --group-directories-first'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status'
alias gd='git diff'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

typeset -A ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[comment]='fg=#7a7a7a'
ZSH_HIGHLIGHT_STYLES[command]='fg=#a8ba9d,bold'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#a8ba9d,bold'
ZSH_HIGHLIGHT_STYLES[function]='fg=#a8ba9d,bold'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#a8ba9d,bold'
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=#a8ba9d,bold'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#a8ba9d,underline'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#c99387,bold'

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#5c6370"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

eval "$(starship init zsh)"
fastfetch
export PATH=$PATH:~/.spicetify
