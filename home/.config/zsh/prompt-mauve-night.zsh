# --- Tema mauve_night para zsh ---
# Agregar al final de tu ~/.zshrc

# Colores de sugerencias (zsh-autosuggestions) — rosa apagado, sutil
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6e5866"

# Colores de resaltado de sintaxis (zsh-syntax-highlighting)
typeset -A ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[default]='fg=#e8dde0'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#c94f6b,bold'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#d9a3b0'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#d9a3b0'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#d9a3b0'
ZSH_HIGHLIGHT_STYLES[function]='fg=#d9a3b0'
ZSH_HIGHLIGHT_STYLES[command]='fg=#e8dde0'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#e8dde0,italic'
ZSH_HIGHLIGHT_STYLES[path]='fg=#b09aa8,underline'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#8b2c4a'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#c9a15a'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#c9a15a'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#c9a15a'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#4a3d4c,italic'

# Prompt: Starship (ver ~/.config/starship.toml)
eval "$(starship init zsh)"

# --- ls bonito con eza (íconos, colores, git status) ---
alias ls='eza --icons --group-directories-first'
alias ll='eza --icons --group-directories-first -l --header --git'
alias la='eza --icons --group-directories-first -la --header --git'
alias lt='eza --icons --group-directories-first --tree --level=2'

# EZA_COLORS: recolorea la salida con nuestra paleta (rosa/magenta/violeta)
# di = directorios, ex = ejecutables, uu/gu = usuario/grupo propio
export EZA_COLORS="di=38;2;217;163;176:ex=38;2;201;79;107:ln=38;2;138;123;163:uu=38;2;122;155;126:gu=38;2;201;161;90"

# --- historial de zsh (esto es lo que probablemente faltaba) ---
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000
setopt EXTENDED_HISTORY       # guarda timestamp de cada comando
setopt HIST_EXPIRE_DUPS_FIRST # al llenarse, borra duplicados primero
setopt HIST_IGNORE_DUPS       # no guarda un comando si es igual al anterior
setopt HIST_IGNORE_ALL_DUPS   # borra duplicados viejos, deja solo el último
setopt HIST_FIND_NO_DUPS      # al buscar (Ctrl+R), no repite resultados
setopt HIST_SAVE_NO_DUPS      # no guarda duplicados al archivo
setopt HIST_VERIFY            # con !! o !n, muestra el comando antes de correrlo
setopt SHARE_HISTORY          # comparte historial en vivo entre terminales abiertas
setopt APPEND_HISTORY         # agrega en vez de sobrescribir
setopt INC_APPEND_HISTORY     # escribe cada comando al toque, no solo al cerrar

# --- sugerencias fantasma (ghost text) mientras escribís, estilo Fish ---
source ~/.config/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6e5866"
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Flecha derecha (o Ctrl+Espacio) para aceptar la sugerencia completa
bindkey '^ ' autosuggest-accept
